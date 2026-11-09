from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import EmployeeProfile
from apps.accounts.permissions import get_role
from apps.projects.models import Project
from apps.tasks.models import Task
from apps.time_tracking.models import TimeEntry


def make_user(name, role):
    user = User.objects.create_user(name, f"{name}@x.com", "pass12345")
    EmployeeProfile.objects.create(user=user, employee_id=f"ID-{name}", role=role)
    if role == "SUPER_ADMIN":
        user.is_staff = True
        user.save()
    return user


class RoleTestBase(APITestCase):
    def setUp(self):
        self.sa = make_user("sa", "SUPER_ADMIN")
        self.hr = make_user("hr", "HR")
        self.mgr = make_user("mgr", "MANAGER")
        self.mgr2 = make_user("mgr2", "MANAGER")
        self.emp = make_user("emp", "EMPLOYEE")

    def auth(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def new_account(self, **extra):
        data = {
            "username": "newbie", "email": "n@x.com", "password": "pass12345",
            "employee_id": "N1", "role": "EMPLOYEE",
        }
        data.update(extra)
        return self.client.post("/api/auth/register/", data, format="json")


class AccountCreationTests(RoleTestBase):
    def test_only_super_admin_creates_accounts(self):
        for user in (self.hr, self.mgr, self.emp):
            self.auth(user)
            self.assertEqual(self.new_account().status_code, 403, user.username)

    def test_super_admin_creates_every_role(self):
        self.auth(self.sa)
        for i, role in enumerate(["HR", "MANAGER", "EMPLOYEE", "SUPER_ADMIN"]):
            res = self.new_account(
                username=f"u{i}", email=f"u{i}@x.com", employee_id=f"X{i}", role=role
            )
            self.assertEqual(res.status_code, 201, res.data)
            user = User.objects.get(username=f"u{i}")
            self.assertEqual(get_role(user), role)
            self.assertEqual(user.is_staff, role == "SUPER_ADMIN")

    def test_old_admin_role_not_accepted_for_new_accounts(self):
        self.auth(self.sa)
        self.assertEqual(self.new_account(role="ADMIN").status_code, 400)

    def test_login_returns_role_and_capabilities(self):
        res = self.client.post(
            "/api/auth/login/", {"username": "hr", "password": "pass12345"}, format="json"
        )
        self.assertEqual(res.data["user"]["role"], "HR")
        caps = res.data["user"]["capabilities"]
        self.assertTrue(caps["manage_employees"])
        self.assertFalse(caps["manage_accounts"])
        self.assertFalse(caps["manage_work"])

    def test_legacy_admin_profile_is_super_admin(self):
        EmployeeProfile.objects.filter(user=self.hr).update(role="ADMIN")
        self.assertEqual(get_role(User.objects.get(pk=self.hr.pk)), "SUPER_ADMIN")


class EmployeeManagementTests(RoleTestBase):
    def url(self, user):
        return f"/api/auth/employees/{user.id}/"

    def test_hr_can_edit_and_deactivate_employee(self):
        self.auth(self.hr)
        res = self.client.patch(self.url(self.emp), {"department": "Ops"}, format="json")
        self.assertEqual(res.status_code, 200)
        res = self.client.patch(self.url(self.emp), {"is_active": False}, format="json")
        self.assertEqual(res.status_code, 200)

    def test_hr_cannot_touch_other_roles_or_change_roles(self):
        self.auth(self.hr)
        for target in (self.mgr, self.sa, self.hr):
            res = self.client.patch(self.url(target), {"department": "x"}, format="json")
            self.assertEqual(res.status_code, 403)
        res = self.client.patch(self.url(self.emp), {"role": "MANAGER"}, format="json")
        self.assertEqual(res.status_code, 403)

    def test_only_super_admin_deletes(self):
        for user in (self.hr, self.mgr):
            self.auth(user)
            self.assertEqual(self.client.delete(self.url(self.emp)).status_code, 403)
        self.auth(self.sa)
        self.assertEqual(self.client.delete(self.url(self.emp)).status_code, 204)

    def test_manager_and_employee_cannot_edit(self):
        self.auth(self.mgr)
        self.assertEqual(
            self.client.patch(self.url(self.emp), {"department": "x"}, format="json").status_code, 403
        )
        self.auth(self.emp)
        self.assertEqual(self.client.patch(self.url(self.emp), {}, format="json").status_code, 403)

    def test_super_admin_can_promote_and_changes_staff_flag(self):
        self.auth(self.sa)
        self.client.patch(self.url(self.emp), {"role": "MANAGER"}, format="json")
        self.emp.refresh_from_db()
        self.assertEqual(get_role(self.emp), "MANAGER")
        self.assertFalse(self.emp.is_staff)

    def test_super_admin_cannot_demote_self(self):
        self.auth(self.sa)
        res = self.client.patch(self.url(self.sa), {"role": "HR"}, format="json")
        self.assertEqual(res.status_code, 400)

    def test_directory_visibility(self):
        self.auth(self.emp)
        self.assertEqual(self.client.get("/api/auth/employees/").status_code, 403)
        self.auth(self.hr)
        self.assertEqual(len(self.client.get("/api/auth/employees/").data), 5)
        self.auth(self.mgr)
        roles = {p["role"] for p in self.client.get("/api/auth/employees/").data}
        self.assertEqual(roles, {"MANAGER", "EMPLOYEE"})


class ManagerWorkTests(RoleTestBase):
    def setUp(self):
        super().setUp()
        self.mine = Project.objects.create(name="Mine", created_by=self.mgr, project_manager=self.mgr)
        self.mine.team_members.add(self.emp)
        self.theirs = Project.objects.create(
            name="Theirs", created_by=self.mgr2, project_manager=self.mgr2
        )
        self.theirs.team_members.add(self.emp, self.mgr)

    def test_manager_creates_project_and_becomes_its_manager(self):
        self.auth(self.mgr)
        res = self.client.post("/api/projects/", {"name": "New"}, format="json")
        self.assertEqual(res.status_code, 201, res.data)
        self.assertEqual(res.data["project_manager"], self.mgr.id)

    def test_manager_edits_only_own_projects(self):
        self.auth(self.mgr)
        ok = self.client.patch(f"/api/projects/{self.mine.id}/", {"name": "Renamed"}, format="json")
        self.assertEqual(ok.status_code, 200)
        no = self.client.patch(f"/api/projects/{self.theirs.id}/", {"name": "Hack"}, format="json")
        self.assertEqual(no.status_code, 404)
        self.assertEqual(self.client.delete(f"/api/projects/{self.theirs.id}/").status_code, 404)
        # but can still read a project they are a team member of
        self.assertEqual(self.client.get(f"/api/projects/{self.theirs.id}/").status_code, 200)

    def test_manager_adds_tasks_only_in_own_projects(self):
        self.auth(self.mgr)
        ok = self.client.post(
            "/api/tasks/", {"project": self.mine.id, "title": "t", "assigned_to": self.emp.id},
            format="json",
        )
        self.assertEqual(ok.status_code, 201, ok.data)
        no = self.client.post(
            "/api/tasks/", {"project": self.theirs.id, "title": "t"}, format="json"
        )
        self.assertEqual(no.status_code, 403)

    def test_manager_only_changes_status_on_foreign_task(self):
        task = Task.objects.create(project=self.theirs, title="x", assigned_to=self.mgr)
        self.auth(self.mgr)
        self.assertEqual(self.client.patch(f"/api/tasks/{task.id}/", {"title": "y"}, format="json").status_code, 403)
        self.assertEqual(self.client.patch(f"/api/tasks/{task.id}/", {"status": "IN_PROGRESS"}, format="json").status_code, 200)
        self.assertEqual(self.client.delete(f"/api/tasks/{task.id}/").status_code, 403)

    def test_manager_task_list_scope(self):
        Task.objects.create(project=self.mine, title="m1", assigned_to=self.emp)
        Task.objects.create(project=self.theirs, title="other", assigned_to=self.emp)
        Task.objects.create(project=self.theirs, title="mine-assigned", assigned_to=self.mgr)
        self.auth(self.mgr)
        titles = {t["title"] for t in self.client.get("/api/tasks/").data}
        self.assertEqual(titles, {"m1", "mine-assigned"})

    def test_manager_reports_scoped_and_limited(self):
        self.auth(self.mgr)
        self.assertEqual(self.client.get("/api/reports/dashboard/").status_code, 200)
        data = self.client.get("/api/reports/projects/").data
        self.assertEqual([p["name"] for p in data["results"]], ["Mine"])
        self.assertEqual(self.client.get("/api/reports/attendance/").status_code, 403)
        self.assertEqual(self.client.get("/api/attendance/manage/").status_code, 403)

    def test_manager_cannot_delete_time_entries_or_clients(self):
        task = Task.objects.create(project=self.mine, title="x", assigned_to=self.emp)
        entry = TimeEntry.objects.create(
            user=self.emp, task=task, date=timezone.localdate(),
            started_at=timezone.now(), status="STOPPED",
        )
        self.auth(self.mgr)
        self.assertEqual(self.client.delete(f"/api/time-tracking/{entry.id}/").status_code, 403)
        self.assertEqual(
            self.client.post("/api/clients/", {"company_name": "C"}, format="json").status_code, 403
        )

    def test_manager_sees_time_entries_of_own_projects_only(self):
        t1 = Task.objects.create(project=self.mine, title="a", assigned_to=self.emp)
        t2 = Task.objects.create(project=self.theirs, title="b", assigned_to=self.emp)
        for t in (t1, t2):
            TimeEntry.objects.create(
                user=self.emp, task=t, date=timezone.localdate(),
                started_at=timezone.now(), status="STOPPED",
            )
        self.auth(self.mgr)
        self.assertEqual(len(self.client.get("/api/time-tracking/").data), 1)
        self.auth(self.sa)
        self.assertEqual(len(self.client.get("/api/time-tracking/").data), 2)


class HRTests(RoleTestBase):
    def test_hr_manages_attendance_and_sees_attendance_report(self):
        self.auth(self.hr)
        self.assertEqual(self.client.get("/api/attendance/manage/").status_code, 200)
        self.assertEqual(self.client.get("/api/reports/attendance/").status_code, 200)
        self.assertEqual(self.client.get("/api/reports/dashboard/").status_code, 200)

    def test_hr_has_no_project_task_or_work_report_access(self):
        self.auth(self.hr)
        self.assertEqual(self.client.post("/api/projects/", {"name": "x"}, format="json").status_code, 403)
        self.assertEqual(self.client.post("/api/tasks/", {"title": "x"}, format="json").status_code, 403)
        self.assertEqual(self.client.get("/api/reports/work-time/").status_code, 403)
        self.assertEqual(self.client.get("/api/reports/projects/").status_code, 403)

    def test_employee_has_no_management_access(self):
        self.auth(self.emp)
        for url in ("/api/attendance/manage/", "/api/reports/dashboard/", "/api/auth/employees/"):
            self.assertEqual(self.client.get(url).status_code, 403, url)
