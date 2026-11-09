from datetime import timedelta

from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.projects.models import Project
from apps.tasks.models import Task
from apps.time_tracking.models import TimeEntry


class ProjectAPITests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user("admin", password="pass12345", is_staff=True)
        self.emp = User.objects.create_user("emp", password="pass12345")
        self.other = User.objects.create_user("other", password="pass12345")
        self.auth(self.admin)

    def auth(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def test_create_with_team(self):
        res = self.client.post(
            "/api/projects/",
            {"name": "  Site  ", "team_members": [self.emp.id], "status": "PLANNING"},
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.data)
        self.assertEqual(res.data["name"], "Site")
        self.assertEqual(res.data["team_members_detail"][0]["username"], "emp")
        self.assertEqual(res.data["total_tasks"], 0)
        self.assertEqual(res.data["progress_percent"], 0)

    def test_deadline_before_start_rejected(self):
        res = self.client.post(
            "/api/projects/",
            {"name": "X", "start_date": "2026-12-10", "deadline": "2026-12-01"},
            format="json",
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("deadline", res.data)

    def test_inactive_user_cannot_join_team(self):
        self.other.is_active = False
        self.other.save()
        res = self.client.post(
            "/api/projects/", {"name": "X", "team_members": [self.other.id]}, format="json"
        )
        self.assertEqual(res.status_code, 400)

    def test_summary_fields(self):
        project = Project.objects.create(
            name="P", created_by=self.admin,
            deadline=timezone.localdate() - timedelta(days=1), status="IN_PROGRESS",
        )
        project.team_members.add(self.emp)
        t1 = Task.objects.create(project=project, title="a", assigned_to=self.emp, status="COMPLETED")
        Task.objects.create(project=project, title="b", assigned_to=self.emp)
        TimeEntry.objects.create(
            user=self.emp, task=t1, date=timezone.localdate(),
            started_at=timezone.now(), duration_seconds=1800, status="STOPPED",
        )
        res = self.client.get(f"/api/projects/{project.id}/")
        self.assertEqual(res.data["total_tasks"], 2)
        self.assertEqual(res.data["completed_tasks"], 1)
        self.assertEqual(res.data["progress_percent"], 50)
        self.assertEqual(res.data["tracked_seconds"], 1800)
        self.assertTrue(res.data["is_overdue"])
        listed = self.client.get("/api/projects/")
        self.assertEqual(listed.data[0]["total_tasks"], 2)

    def test_cannot_remove_member_with_open_tasks(self):
        project = Project.objects.create(name="P", created_by=self.admin)
        project.team_members.add(self.emp, self.other)
        task = Task.objects.create(project=project, title="a", assigned_to=self.emp)
        res = self.client.patch(
            f"/api/projects/{project.id}/", {"team_members": [self.other.id]}, format="json"
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("emp", str(res.data["team_members"]))
        Task.objects.filter(pk=task.pk).update(status="COMPLETED")
        res = self.client.patch(
            f"/api/projects/{project.id}/", {"team_members": [self.other.id]}, format="json"
        )
        self.assertEqual(res.status_code, 200)

    def test_employee_sees_only_own_projects_and_cannot_edit(self):
        mine = Project.objects.create(name="mine", created_by=self.admin)
        mine.team_members.add(self.emp)
        Project.objects.create(name="other", created_by=self.admin)
        self.auth(self.emp)
        self.assertEqual([p["name"] for p in self.client.get("/api/projects/").data], ["mine"])
        self.assertEqual(
            self.client.patch(f"/api/projects/{mine.id}/", {"name": "x"}, format="json").status_code, 403
        )
