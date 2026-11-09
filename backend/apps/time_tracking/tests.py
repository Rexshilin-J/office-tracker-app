from datetime import timedelta

from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.attendance.models import Attendance
from apps.projects.models import Project
from apps.tasks.models import Task
from apps.time_tracking.models import TimeEntry


class TimeTrackingAPITests(APITestCase):
    URL = "/api/time-tracking/"

    def setUp(self):
        self.admin = User.objects.create_user("admin", password="pass12345", is_staff=True)
        self.emp = User.objects.create_user("emp", password="pass12345")
        self.other = User.objects.create_user("other", password="pass12345")
        project = Project.objects.create(name="Site", created_by=self.admin)
        project.team_members.add(self.emp, self.other)
        self.task = Task.objects.create(project=project, title="t", assigned_to=self.emp)
        self.task2 = Task.objects.create(project=project, title="t2", assigned_to=self.emp)
        token, _ = Token.objects.get_or_create(user=self.emp)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def check_in(self, user=None):
        Attendance.objects.create(
            user=user or self.emp, check_in=timezone.now(), status="PRESENT"
        )

    def act(self, action, **extra):
        return self.client.post(self.URL, {"action": action, **extra}, format="json")

    def test_start_requires_check_in(self):
        res = self.act("start", task=self.task.id)
        self.assertEqual(res.status_code, 400)

    def test_start_requires_assigned_task(self):
        self.check_in()
        other_task = Task.objects.create(
            project=self.task.project, title="x", assigned_to=self.other
        )
        res = self.act("start", task=other_task.id)
        self.assertEqual(res.status_code, 403)

    def test_start_moves_todo_to_in_progress(self):
        self.check_in()
        res = self.act("start", task=self.task.id)
        self.assertEqual(res.status_code, 201)
        self.task.refresh_from_db()
        self.assertEqual(self.task.status, "IN_PROGRESS")

    def test_no_second_active_timer(self):
        self.check_in()
        self.act("start", task=self.task.id)
        res = self.act("start", task=self.task2.id)
        self.assertEqual(res.status_code, 400)
        self.assertEqual(TimeEntry.objects.filter(status="RUNNING").count(), 1)

    def test_invalid_transitions(self):
        self.check_in()
        self.assertEqual(self.act("pause").status_code, 400)
        self.assertEqual(self.act("resume").status_code, 400)
        self.assertEqual(self.act("stop").status_code, 400)
        self.act("start", task=self.task.id)
        self.assertEqual(self.act("resume").status_code, 400)
        self.act("pause")
        self.assertEqual(self.act("pause").status_code, 400)

    def test_duration_excludes_paused_time(self):
        self.check_in()
        self.act("start", task=self.task.id)
        entry = TimeEntry.objects.get()
        now = timezone.now()
        # 100 min since start, of which a 30 min pause was already resumed.
        TimeEntry.objects.filter(pk=entry.pk).update(
            started_at=now - timedelta(minutes=100), paused_seconds=30 * 60
        )
        res = self.act("stop")
        self.assertEqual(res.status_code, 200)
        entry.refresh_from_db()
        self.assertEqual(entry.status, "STOPPED")
        self.assertAlmostEqual(entry.duration_seconds, 70 * 60, delta=5)

    def test_stop_while_paused_counts_pause_as_paused(self):
        self.check_in()
        self.act("start", task=self.task.id)
        entry = TimeEntry.objects.get()
        now = timezone.now()
        TimeEntry.objects.filter(pk=entry.pk).update(
            started_at=now - timedelta(minutes=60),
            status="PAUSED",
            paused_at=now - timedelta(minutes=20),
        )
        self.act("stop")
        entry.refresh_from_db()
        self.assertAlmostEqual(entry.duration_seconds, 40 * 60, delta=5)

    def test_cannot_start_on_completed_task(self):
        self.check_in()
        Task.objects.filter(pk=self.task.pk).update(status="COMPLETED")
        self.assertEqual(self.act("start", task=self.task.id).status_code, 400)

    def test_checkout_stops_active_timer(self):
        self.check_in()
        self.act("start", task=self.task.id)
        res = self.client.post("/api/attendance/", {"action": "check_out"}, format="json")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(TimeEntry.objects.get().status, "STOPPED")

    def test_cannot_start_after_checkout(self):
        self.check_in()
        self.client.post("/api/attendance/", {"action": "check_out"}, format="json")
        self.assertEqual(self.act("start", task=self.task.id).status_code, 400)

    def test_employee_lists_only_own_entries(self):
        self.check_in()
        self.act("start", task=self.task.id)
        TimeEntry.objects.create(
            user=self.other, task=self.task, date=timezone.localdate(),
            started_at=timezone.now(), status="STOPPED",
        )
        res = self.client.get(self.URL)
        self.assertEqual(len(res.data), 1)

    def test_active_endpoint(self):
        self.assertFalse(self.client.get(self.URL + "active/").data["active"])
        self.check_in()
        self.act("start", task=self.task.id)
        self.assertTrue(self.client.get(self.URL + "active/").data["active"])
