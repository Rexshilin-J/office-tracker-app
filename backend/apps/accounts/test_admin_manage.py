from datetime import timedelta

from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import EmployeeProfile
from apps.attendance.models import Attendance
from apps.projects.models import Project
from apps.tasks.models import Task
from apps.time_tracking.models import TimeEntry


class AdminManageTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user("admin", "a@x.com", "pass12345", is_staff=True)
        self.emp = User.objects.create_user("emp", "e@x.com", "pass12345")
        EmployeeProfile.objects.create(user=self.emp, employee_id="E1")
        self.auth(self.admin)

    def auth(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    # ---- employees
    def test_edit_employee_and_promote(self):
        res = self.client.patch(
            f"/api/auth/employees/{self.emp.id}/",
            {"department": "IT", "role": "SUPER_ADMIN", "phone": "99999"}, format="json",
        )
        self.assertEqual(res.status_code, 200)
        self.emp.refresh_from_db()
        self.assertTrue(self.emp.is_staff)
        self.assertEqual(self.emp.employee_profile.department, "IT")

    def test_reset_password(self):
        self.client.patch(
            f"/api/auth/employees/{self.emp.id}/", {"password": "newpass123"}, format="json"
        )
        res = self.client.post(
            "/api/auth/login/", {"username": "emp", "password": "newpass123"}, format="json"
        )
        self.assertEqual(res.status_code, 200)

    def test_deactivate_blocks_login_and_token(self):
        self.auth(self.emp)
        old = Token.objects.get(user=self.emp).key
        self.auth(self.admin)
        self.client.patch(f"/api/auth/employees/{self.emp.id}/", {"is_active": False}, format="json")
        self.assertFalse(Token.objects.filter(key=old).exists())
        res = self.client.post(
            "/api/auth/login/", {"username": "emp", "password": "pass12345"}, format="json"
        )
        self.assertEqual(res.status_code, 400)

    def test_duplicate_employee_id_rejected(self):
        other = User.objects.create_user("o", "o@x.com", "pass12345")
        EmployeeProfile.objects.create(user=other, employee_id="E2")
        res = self.client.patch(
            f"/api/auth/employees/{other.id}/", {"employee_id": "E1"}, format="json"
        )
        self.assertEqual(res.status_code, 400)

    def test_cannot_delete_or_deactivate_self(self):
        self.assertEqual(self.client.delete(f"/api/auth/employees/{self.admin.id}/").status_code, 400)
        res = self.client.patch(
            f"/api/auth/employees/{self.admin.id}/", {"is_active": False}, format="json"
        )
        self.assertEqual(res.status_code, 400)

    def test_delete_employee_keeps_projects_and_tasks(self):
        project = Project.objects.create(name="P", created_by=self.emp)
        project.team_members.add(self.emp)
        task = Task.objects.create(project=project, title="t", assigned_to=self.emp)
        Attendance.objects.create(user=self.emp, check_in=timezone.now())
        res = self.client.delete(f"/api/auth/employees/{self.emp.id}/")
        self.assertEqual(res.status_code, 204)
        task.refresh_from_db()
        self.assertIsNone(task.assigned_to)
        self.assertTrue(Project.objects.filter(pk=project.pk).exists())
        self.assertFalse(Attendance.objects.exists())

    def test_employee_cannot_manage_employees(self):
        self.auth(self.emp)
        self.assertEqual(self.client.delete(f"/api/auth/employees/{self.admin.id}/").status_code, 403)

    # ---- attendance
    def test_attendance_admin_crud(self):
        day = str(timezone.localdate() - timedelta(days=3))
        cin = timezone.now() - timedelta(days=3, hours=8)
        cout = cin + timedelta(hours=8)
        res = self.client.post(
            "/api/attendance/manage/",
            {"user": self.emp.id, "date": day, "check_in": cin.isoformat(),
             "check_out": cout.isoformat(), "status": "PRESENT"},
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.data)
        self.assertEqual(res.data["worked_seconds"], 8 * 3600)
        rid = res.data["id"]

        dup = self.client.post(
            "/api/attendance/manage/",
            {"user": self.emp.id, "date": day, "check_in": cin.isoformat()}, format="json",
        )
        self.assertEqual(dup.status_code, 400)

        listed = self.client.get(f"/api/attendance/manage/?date={day}")
        self.assertEqual(len(listed.data), 1)

        bad = self.client.patch(
            f"/api/attendance/manage/{rid}/", {"check_out": cin.isoformat()}, format="json"
        )
        self.assertEqual(bad.status_code, 400)

        self.assertEqual(self.client.patch(
            f"/api/attendance/manage/{rid}/", {"status": "HALF_DAY"}, format="json").status_code, 200)
        self.assertEqual(self.client.delete(f"/api/attendance/manage/{rid}/").status_code, 204)

    def test_attendance_manage_admin_only(self):
        self.auth(self.emp)
        self.assertEqual(self.client.get("/api/attendance/manage/").status_code, 403)

    # ---- time entries
    def test_admin_deletes_time_entry(self):
        project = Project.objects.create(name="P")
        task = Task.objects.create(project=project, title="t", assigned_to=self.emp)
        entry = TimeEntry.objects.create(
            user=self.emp, task=task, date=timezone.localdate(),
            started_at=timezone.now(), status="STOPPED",
        )
        self.auth(self.emp)
        self.assertEqual(self.client.delete(f"/api/time-tracking/{entry.id}/").status_code, 403)
        self.auth(self.admin)
        self.assertEqual(self.client.delete(f"/api/time-tracking/{entry.id}/").status_code, 204)
        self.assertEqual(self.client.delete(f"/api/time-tracking/{entry.id}/").status_code, 404)
