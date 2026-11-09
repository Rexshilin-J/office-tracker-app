from datetime import timedelta

from django.contrib.auth import get_user_model
from django.db.models import Count, DurationField, ExpressionWrapper, F, Q, Sum
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework.authentication import TokenAuthentication
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import (
    capability,
    managed_projects,
    managed_tasks,
    managed_time_entries,
)
from apps.attendance.models import Attendance
from apps.projects.models import Project
from apps.tasks.models import Task
from apps.time_tracking.models import TimeEntry

User = get_user_model()


def get_date_range(request):
    """Reads ?date_from & ?date_to (YYYY-MM-DD). Defaults to the last 30 days."""
    today = timezone.localdate()
    raw_from = request.query_params.get("date_from")
    raw_to = request.query_params.get("date_to")

    date_to = parse_date(raw_to) if raw_to else today
    date_from = parse_date(raw_from) if raw_from else date_to - timedelta(days=29)

    if date_from is None or date_to is None:
        raise ValidationError("Dates must be in YYYY-MM-DD format.")
    if date_from > date_to:
        raise ValidationError("date_from cannot be after date_to.")
    return date_from, date_to


def seconds(value):
    return int(value.total_seconds()) if value else 0


class ReportView(APIView):
    authentication_classes = [TokenAuthentication]


class AttendanceReportBase(ReportView):
    permission_classes = [capability("view_attendance_report")]


class WorkReportBase(ReportView):
    """Project/task/time reports - scoped to the projects the user manages."""

    permission_classes = [capability("view_work_reports")]


class AttendanceReportAPIView(AttendanceReportBase):
    """GET /api/reports/attendance/?date_from=&date_to=&user="""

    def get(self, request):
        date_from, date_to = get_date_range(request)
        records = Attendance.objects.filter(date__range=(date_from, date_to))
        if request.query_params.get("user"):
            records = records.filter(user=request.query_params["user"])

        worked = ExpressionWrapper(
            F("check_out") - F("check_in"), output_field=DurationField()
        )
        rows = (
            records.values("user", "user__username")
            .annotate(
                days_present=Count("id", filter=Q(status="PRESENT")),
                half_days=Count("id", filter=Q(status="HALF_DAY")),
                days_absent=Count("id", filter=Q(status="ABSENT")),
                missing_check_out=Count(
                    "id", filter=Q(check_in__isnull=False, check_out__isnull=True)
                ),
                worked=Sum(worked, filter=Q(check_out__isnull=False)),
            )
            .order_by("user__username")
        )

        return Response(
            {
                "date_from": date_from,
                "date_to": date_to,
                "results": [
                    {
                        "user_id": r["user"],
                        "username": r["user__username"],
                        "days_present": r["days_present"],
                        "half_days": r["half_days"],
                        "days_absent": r["days_absent"],
                        "missing_check_out": r["missing_check_out"],
                        "worked_seconds": seconds(r["worked"]),
                    }
                    for r in rows
                ],
            }
        )


class ProjectReportAPIView(WorkReportBase):
    """GET /api/reports/projects/ -> task progress and tracked time per project."""

    def get(self, request):
        date_from, date_to = get_date_range(request)

        projects = managed_projects(request.user).select_related("client").annotate(
            total_tasks=Count("tasks", distinct=True),
            completed_tasks=Count(
                "tasks", filter=Q(tasks__status="COMPLETED"), distinct=True
            ),
            tracked=Sum(
                "tasks__time_entries__duration_seconds",
                filter=Q(
                    tasks__time_entries__status="STOPPED",
                    tasks__time_entries__date__range=(date_from, date_to),
                ),
            ),
        )

        results = []
        for p in projects:
            progress = (
                round(p.completed_tasks * 100 / p.total_tasks)
                if p.total_tasks
                else 0
            )
            results.append(
                {
                    "project_id": p.id,
                    "name": p.name,
                    "client": p.client.company_name if p.client else None,
                    "status": p.status,
                    "priority": p.priority,
                    "deadline": p.deadline,
                    "total_tasks": p.total_tasks,
                    "completed_tasks": p.completed_tasks,
                    "progress_percent": progress,
                    "tracked_seconds": p.tracked or 0,
                }
            )

        return Response(
            {"date_from": date_from, "date_to": date_to, "results": results}
        )


class TaskReportAPIView(WorkReportBase):
    """GET /api/reports/tasks/ -> counts by status, priority and per employee."""

    def get(self, request):
        tasks = managed_tasks(request.user)
        if request.query_params.get("project"):
            tasks = tasks.filter(project=request.query_params["project"])

        today = timezone.localdate()
        by_status = {s: 0 for s, _ in Task.STATUS_CHOICES}
        for row in tasks.values("status").annotate(n=Count("id")):
            by_status[row["status"]] = row["n"]

        by_priority = {p: 0 for p, _ in Task.PRIORITY_CHOICES}
        for row in tasks.values("priority").annotate(n=Count("id")):
            by_priority[row["priority"]] = row["n"]

        per_employee = (
            tasks.filter(assigned_to__isnull=False)
            .values("assigned_to", "assigned_to__username")
            .annotate(
                total=Count("id"),
                completed=Count("id", filter=Q(status="COMPLETED")),
                overdue=Count(
                    "id", filter=Q(due_date__lt=today) & ~Q(status="COMPLETED")
                ),
            )
            .order_by("assigned_to__username")
        )

        return Response(
            {
                "total": tasks.count(),
                "unassigned": tasks.filter(assigned_to__isnull=True).count(),
                "overdue": tasks.filter(due_date__lt=today)
                .exclude(status="COMPLETED")
                .count(),
                "by_status": by_status,
                "by_priority": by_priority,
                "per_employee": [
                    {
                        "user_id": r["assigned_to"],
                        "username": r["assigned_to__username"],
                        "total": r["total"],
                        "completed": r["completed"],
                        "overdue": r["overdue"],
                    }
                    for r in per_employee
                ],
            }
        )


class WorkTimeReportAPIView(WorkReportBase):
    """GET /api/reports/work-time/?date_from=&date_to=&user=&project="""

    def get(self, request):
        date_from, date_to = get_date_range(request)
        entries = managed_time_entries(request.user).filter(
            status="STOPPED", date__range=(date_from, date_to)
        )
        if request.query_params.get("user"):
            entries = entries.filter(user=request.query_params["user"])
        if request.query_params.get("project"):
            entries = entries.filter(task__project=request.query_params["project"])

        per_user = (
            entries.values("user", "user__username")
            .annotate(total=Sum("duration_seconds"), sessions=Count("id"))
            .order_by("user__username")
        )
        per_task = (
            entries.values("task", "task__title", "task__project__name")
            .annotate(total=Sum("duration_seconds"), sessions=Count("id"))
            .order_by("-total")
        )

        return Response(
            {
                "date_from": date_from,
                "date_to": date_to,
                "total_seconds": entries.aggregate(t=Sum("duration_seconds"))["t"] or 0,
                "per_user": [
                    {
                        "user_id": r["user"],
                        "username": r["user__username"],
                        "total_seconds": r["total"] or 0,
                        "sessions": r["sessions"],
                    }
                    for r in per_user
                ],
                "per_task": [
                    {
                        "task_id": r["task"],
                        "task": r["task__title"],
                        "project": r["task__project__name"],
                        "total_seconds": r["total"] or 0,
                        "sessions": r["sessions"],
                    }
                    for r in per_task
                ],
            }
        )


class DashboardAPIView(ReportView):
    """GET /api/reports/dashboard/ -> one-call summary for the management home screen."""

    permission_classes = [capability("view_dashboard")]

    def get(self, request):
        today = timezone.localdate()
        now = timezone.now()

        # Admins are not "employees" for attendance numbers.
        staff = User.objects.filter(is_active=True, is_staff=False, is_superuser=False)
        total_employees = staff.count()

        todays = Attendance.objects.filter(
            date=today, user__in=staff, check_in__isnull=False
        ).select_related("user")
        checked_in = todays.count()
        checked_out = todays.filter(check_out__isnull=False).count()

        my_projects = managed_projects(request.user)
        tasks = managed_tasks(request.user)
        overdue = tasks.filter(due_date__lt=today).exclude(status="COMPLETED").count()

        my_entries = managed_time_entries(request.user)
        today_seconds = (
            my_entries.filter(status="STOPPED", date=today).aggregate(
                t=Sum("duration_seconds")
            )["t"]
            or 0
        )

        # Running/paused timers, whatever day they were started on.
        active_entries = my_entries.filter(
            status__in=["RUNNING", "PAUSED"]
        ).select_related("user", "task")

        return Response(
            {
                "date": today,
                "employees": {
                    "total": total_employees,
                    "checked_in_today": checked_in,
                    "checked_out_today": checked_out,
                    "still_working": checked_in - checked_out,
                    "not_checked_in": max(0, total_employees - checked_in),
                },
                "projects": {
                    "total": my_projects.count(),
                    "in_progress": my_projects.filter(status="IN_PROGRESS").count(),
                    "completed": my_projects.filter(status="COMPLETED").count(),
                },
                "tasks": {
                    "total": tasks.count(),
                    "todo": tasks.filter(status="TODO").count(),
                    "in_progress": tasks.filter(status="IN_PROGRESS").count(),
                    "in_review": tasks.filter(status="IN_REVIEW").count(),
                    "completed": tasks.filter(status="COMPLETED").count(),
                    "overdue": overdue,
                },
                "active_timers": active_entries.count(),
                "tracked_seconds_today": today_seconds,
                "active_timer_list": [
                    {
                        "username": e.user.username,
                        "task_title": e.task.title,
                        "status": e.status,
                        "elapsed_seconds": e.elapsed_seconds(now),
                    }
                    for e in active_entries
                ],
                "attendance_today": [
                    {
                        "username": a.user.username,
                        "check_in": a.check_in,
                        "check_out": a.check_out,
                    }
                    for a in todays.order_by("check_in")
                ],
            }
        )
