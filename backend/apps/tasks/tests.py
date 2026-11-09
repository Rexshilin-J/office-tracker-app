from datetime import timedelta

from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.projects.models import Project
from apps.tasks.models import Task


class TaskAPITests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user("admin", password="pass12345", is_staff=True)
        self.emp = User.objects.create_user("emp", password="pass12345")
        self.other = User.objects.create_user("other", password="pass12345")
        self.project = Project.objects.create(name="Site", created_by=self.admin)
        self.project.team_members.add(self.emp)

    def auth(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def payload(self, **extra):
        data = {"project": self.project.id, "title": "Design home", "assigned_to": self.emp.id}
        data.update(extra)
        return data

    def test_admin_creates_task(self):
        self.auth(self.admin)
        res = self.client.post("/api/tasks/", self.payload(), format="json")
        self.assertEqual(res.status_code, 201)
        self.assertEqual(res.data["status"], "TODO")

    def test_employee_cannot_create_task(self):
        self.auth(self.emp)
        res = self.client.post("/api/tasks/", self.payload(), format="json")
        self.assertEqual(res.status_code, 403)

    def test_assignee_must_be_project_member(self):
        self.auth(self.admin)
        res = self.client.post(
            "/api/tasks/", self.payload(assigned_to=self.other.id), format="json"
        )
        self.assertEqual(res.status_code, 400)

    def test_past_due_date_rejected(self):
        self.auth(self.admin)
        past = str(timezone.localdate() - timedelta(days=1))
        res = self.client.post("/api/tasks/", self.payload(due_date=past), format="json")
        self.assertEqual(res.status_code, 400)

    def test_employee_sees_only_own_tasks(self):
        Task.objects.create(project=self.project, title="mine", assigned_to=self.emp)
        Task.objects.create(project=self.project, title="not mine")
        self.auth(self.emp)
        res = self.client.get("/api/tasks/")
        self.assertEqual([t["title"] for t in res.data], ["mine"])

    def test_employee_can_only_change_status(self):
        task = Task.objects.create(project=self.project, title="t", assigned_to=self.emp)
        self.auth(self.emp)
        res = self.client.patch(f"/api/tasks/{task.id}/", {"title": "hack"}, format="json")
        self.assertEqual(res.status_code, 403)
        res = self.client.patch(f"/api/tasks/{task.id}/", {"status": "IN_PROGRESS"}, format="json")
        self.assertEqual(res.status_code, 200)

    def test_employee_cannot_open_others_task(self):
        task = Task.objects.create(project=self.project, title="t", assigned_to=self.emp)
        self.auth(self.other)
        self.assertEqual(self.client.get(f"/api/tasks/{task.id}/").status_code, 404)

    def test_invalid_status_transition(self):
        task = Task.objects.create(project=self.project, title="t", assigned_to=self.emp)
        self.auth(self.emp)
        res = self.client.patch(f"/api/tasks/{task.id}/", {"status": "COMPLETED"}, format="json")
        self.assertEqual(res.status_code, 400)

    def test_completed_sets_and_reopen_clears_completed_at(self):
        task = Task.objects.create(
            project=self.project, title="t", assigned_to=self.emp, status="IN_PROGRESS"
        )
        self.auth(self.emp)
        self.client.patch(f"/api/tasks/{task.id}/", {"status": "COMPLETED"}, format="json")
        task.refresh_from_db()
        self.assertIsNotNone(task.completed_at)
        self.client.patch(f"/api/tasks/{task.id}/", {"status": "IN_PROGRESS"}, format="json")
        task.refresh_from_db()
        self.assertIsNone(task.completed_at)

    def test_only_admin_deletes(self):
        task = Task.objects.create(project=self.project, title="t", assigned_to=self.emp)
        self.auth(self.emp)
        self.assertEqual(self.client.delete(f"/api/tasks/{task.id}/").status_code, 403)
        self.auth(self.admin)
        self.assertEqual(self.client.delete(f"/api/tasks/{task.id}/").status_code, 204)
