from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import (
    MANAGER,
    SUPER_ADMIN,
    capability,
    get_role,
    visible_time_entries,
)
from apps.attendance.models import Attendance
from apps.tasks.models import Task

from .models import TimeEntry
from .serializers import TimeEntrySerializer
from .services import stop_entry


def bad_request(message):
    return Response({"detail": message}, status=status.HTTP_400_BAD_REQUEST)


class TimeTrackingAPIView(APIView):
    """
    GET  /api/time-tracking/          -> list entries (own; admin can use ?user=)
    POST /api/time-tracking/          -> {"action": "start|pause|resume|stop", "task": id}
    """

    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queryset = visible_time_entries(request.user).select_related("user", "task")

        if get_role(request.user) in (SUPER_ADMIN, MANAGER):
            if request.query_params.get("user"):
                queryset = queryset.filter(user=request.query_params["user"])

        params = request.query_params
        if params.get("task"):
            queryset = queryset.filter(task=params["task"])
        if params.get("date_from"):
            queryset = queryset.filter(date__gte=params["date_from"])
        if params.get("date_to"):
            queryset = queryset.filter(date__lte=params["date_to"])

        return Response(TimeEntrySerializer(queryset[:200], many=True).data)

    @transaction.atomic
    def post(self, request):
        action = request.data.get("action")
        handler = {
            "start": self.start,
            "pause": self.pause,
            "resume": self.resume,
            "stop": self.stop,
        }.get(action)

        if handler is None:
            return bad_request("Use action: start, pause, resume or stop.")
        return handler(request)

    # ---- helpers -------------------------------------------------------
    def active_entry(self, user):
        return (
            TimeEntry.objects.select_for_update()
            .select_related("task", "user")
            .filter(user=user, status__in=["RUNNING", "PAUSED"])
            .first()
        )

    def respond(self, entry, message, code=status.HTTP_200_OK):
        return Response(
            {"message": message, "entry": TimeEntrySerializer(entry).data},
            status=code,
        )

    # ---- actions -------------------------------------------------------
    def start(self, request):
        task_id = request.data.get("task")
        if not task_id:
            return bad_request("task is required to start a timer.")

        try:
            task = Task.objects.select_related("project").get(pk=task_id)
        except (Task.DoesNotExist, ValueError, TypeError):
            return bad_request("Task not found.")

        if task.assigned_to_id != request.user.id:
            return Response(
                {"detail": "This task is not assigned to you."},
                status=status.HTTP_403_FORBIDDEN,
            )

        if task.status == "COMPLETED":
            return bad_request("Cannot track time on a completed task.")

        today = timezone.localdate()
        attendance = Attendance.objects.filter(user=request.user, date=today).first()
        if not attendance or not attendance.check_in:
            return bad_request("Please check in before starting a timer.")
        if attendance.check_out:
            return bad_request("You have already checked out today.")

        if self.active_entry(request.user):
            return bad_request(
                "You already have an active timer. Stop it before starting another."
            )

        try:
            with transaction.atomic():
                entry = TimeEntry.objects.create(
                    user=request.user,
                    task=task,
                    date=today,
                    started_at=timezone.now(),
                    status="RUNNING",
                )
        except IntegrityError:
            return bad_request("You already have an active timer.")

        if task.status == "TODO":
            task.status = "IN_PROGRESS"
            task.save(update_fields=["status", "updated_at"])

        return self.respond(entry, "Timer started.", status.HTTP_201_CREATED)

    def pause(self, request):
        entry = self.active_entry(request.user)
        if not entry:
            return bad_request("No active timer to pause.")
        if entry.status != "RUNNING":
            return bad_request("Timer is already paused.")

        entry.status = "PAUSED"
        entry.paused_at = timezone.now()
        entry.save(update_fields=["status", "paused_at", "updated_at"])
        return self.respond(entry, "Timer paused.")

    def resume(self, request):
        entry = self.active_entry(request.user)
        if not entry:
            return bad_request("No active timer to resume.")
        if entry.status != "PAUSED":
            return bad_request("Timer is not paused.")

        now = timezone.now()
        entry.paused_seconds += int((now - entry.paused_at).total_seconds())
        entry.paused_at = None
        entry.status = "RUNNING"
        entry.save(update_fields=["status", "paused_at", "paused_seconds", "updated_at"])
        return self.respond(entry, "Timer resumed.")

    def stop(self, request):
        entry = self.active_entry(request.user)
        if not entry:
            return bad_request("No active timer to stop.")

        stop_entry(entry)
        return self.respond(entry, "Timer stopped.")


class ActiveTimerAPIView(APIView):
    """GET /api/time-tracking/active/ -> current user's running/paused timer."""

    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request):
        entry = (
            TimeEntry.objects.select_related("user", "task")
            .filter(user=request.user, status__in=["RUNNING", "PAUSED"])
            .first()
        )
        if not entry:
            return Response({"active": False, "entry": None})
        return Response({"active": True, "entry": TimeEntrySerializer(entry).data})


class TimeEntryDeleteAPIView(APIView):
    """DELETE /api/time-tracking/<id>/ - admin only."""

    authentication_classes = [TokenAuthentication]
    permission_classes = [capability("delete_time_entries")]

    def delete(self, request, pk):
        deleted, _ = TimeEntry.objects.filter(pk=pk).delete()
        if not deleted:
            return Response({"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND)
        return Response(status=status.HTTP_204_NO_CONTENT)
