from datetime import timedelta

from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.attendance.models import Attendance
from apps.projects.models import Project
from apps.tasks.models import Task
from apps.time_tracking.models import TimeEntry


class ReportAPITests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user("admin", password="pass12345", is_staff=True)
        self.emp = User.objects.create_user("emp", password="pass12345")
        self.project = Project.objects.create(name="Site", created_by=self.admin)
        self.project.team_members.add(self.emp)
        today = timezone.localdate()
        self.t1 = Task.objects.create(
            project=self.project, title="a", assigned_to=self.emp, status="COMPLETED"
        )
        self.t2 = Task.objects.create(
            project=self.project, title="b", assigned_to=self.emp,
            due_date=today - timedelta(days=2),
        )
        now = timezone.now()
        Attendance.objects.create(
            user=self.emp, check_in=now - timedelta(hours=8), check_out=now
        )
        TimeEntry.objects.create(
            user=self.emp, task=self.t1, date=today, started_at=now,
            duration_seconds=3600, status="STOPPED",
        )
        self.login(self.admin)

    def login(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def test_employee_blocked_from_reports(self):
        self.login(self.emp)
        for name in ["dashboard", "attendance", "projects", "tasks", "work-time"]:
            self.assertEqual(self.client.get(f"/api/reports/{name}/").status_code, 403)

    def test_attendance_report(self):
        res = self.client.get("/api/reports/attendance/")
        row = res.data["results"][0]
        self.assertEqual(row["username"], "emp")
        self.assertEqual(row["days_present"], 1)
        self.assertAlmostEqual(row["worked_seconds"], 8 * 3600, delta=5)

    def test_project_report(self):
        row = self.client.get("/api/reports/projects/").data["results"][0]
        self.assertEqual(row["total_tasks"], 2)
        self.assertEqual(row["completed_tasks"], 1)
        self.assertEqual(row["progress_percent"], 50)
        self.assertEqual(row["tracked_seconds"], 3600)

    def test_task_report(self):
        data = self.client.get("/api/reports/tasks/").data
        self.assertEqual(data["total"], 2)
        self.assertEqual(data["overdue"], 1)
        self.assertEqual(data["by_status"]["COMPLETED"], 1)

    def test_work_time_report(self):
        data = self.client.get("/api/reports/work-time/").data
        self.assertEqual(data["total_seconds"], 3600)
        self.assertEqual(data["per_user"][0]["username"], "emp")

    def test_dashboard(self):
        data = self.client.get("/api/reports/dashboard/").data
        self.assertEqual(data["employees"]["checked_in_today"], 1)
        self.assertEqual(data["tasks"]["overdue"], 1)

    def test_bad_date_rejected(self):
        res = self.client.get("/api/reports/attendance/?date_from=junk")
        self.assertEqual(res.status_code, 400)

    def test_dashboard_ignores_admins_and_lists_live_data(self):
        now = timezone.now()
        Attendance.objects.create(user=self.admin, check_in=now)
        TimeEntry.objects.create(
            user=self.emp, task=self.t2, date=timezone.localdate() - timedelta(days=1),
            started_at=now - timedelta(minutes=5), status="RUNNING",
        )
        data = self.client.get("/api/reports/dashboard/").data
        self.assertEqual(data["employees"]["total"], 1)
        self.assertEqual(data["employees"]["checked_in_today"], 1)
        self.assertEqual(data["employees"]["not_checked_in"], 0)
        self.assertEqual(len(data["attendance_today"]), 1)
        self.assertEqual(data["active_timer_list"][0]["username"], "emp")
        self.assertGreaterEqual(data["active_timer_list"][0]["elapsed_seconds"], 290)
