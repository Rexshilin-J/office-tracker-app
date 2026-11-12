"""
End-to-end check of the Employee module's API contract.

Each step makes the same request, with the same payload, that a Flutter screen
makes, and asserts the JSON keys that screen reads. If a backend change ever
renames or drops one of these fields, this test fails before the app does.
"""
from datetime import timedelta

from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.accounts.models import EmployeeProfile
from apps.projects.models import Project
from apps.tasks.models import Task


def keys(testcase, data, *names):
    for n in names:
        testcase.assertIn(n, data, f"response is missing '{n}': {sorted(data)}")


class EmployeeJourney(APITestCase):
    def setUp(self):
        self.mgr = User.objects.create_user("mgr", password="pass12345")
        EmployeeProfile.objects.create(user=self.mgr, employee_id="M01", role="MANAGER")
        self.emp = User.objects.create_user("priya", email="priya@x.com", password="pass12345")
        EmployeeProfile.objects.create(
            user=self.emp, employee_id="E042", phone="9876543210", role="EMPLOYEE",
            department="Engineering", designation="Developer", work_mode="HYBRID",
        )
        self.rival = User.objects.create_user("rival", password="pass12345")
        today = timezone.localdate()
        self.proj = Project.objects.create(
            name="Website", description="Revamp", project_manager=self.mgr, created_by=self.mgr,
            status="IN_PROGRESS", start_date=today - timedelta(days=5),
            deadline=today + timedelta(days=20),
        )
        self.proj.team_members.add(self.emp, self.rival)
        self.other_proj = Project.objects.create(name="Secret", created_by=self.mgr)
        self.t1 = Task.objects.create(project=self.proj, title="Build login", description="OAuth",
                                      assigned_to=self.emp, created_by=self.mgr, due_date=today + timedelta(days=2))
        self.t2 = Task.objects.create(project=self.proj, title="Write docs", assigned_to=self.emp, created_by=self.mgr)
        self.rival_task = Task.objects.create(project=self.proj, title="Rival work", assigned_to=self.rival, created_by=self.mgr)
        Task.objects.create(project=self.other_proj, title="Hidden", created_by=self.mgr)

    def login(self, username="priya"):
        res = self.client.post("/api/auth/login/", {"username": username, "password": "pass12345"}, format="json")
        self.assertEqual(res.status_code, 200)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {res.data['token']}")
        return res.data

    # ------------------------------------------------------------------
    def test_full_day(self):
        # ---- 1. login -> employee routing + profile ------------------------
        data = self.login()
        keys(self, data, "token", "user")
        user = data["user"]
        self.assertEqual(user["role"], "EMPLOYEE")                    # Session.isEmployee
        keys(self, user, "id", "username", "email", "employee_id", "department",
             "designation", "work_mode", "phone", "capabilities")      # Profile screen
        self.assertEqual((user["employee_id"], user["department"], user["designation"], user["work_mode"]),
                         ("E042", "Engineering", "Developer", "HYBRID"))
        me = self.client.get("/api/auth/me/").data
        self.assertEqual(me["employee_id"], "E042")
        # employees must NOT get management capabilities
        self.assertFalse(any(user["capabilities"].values()), user["capabilities"])

        # ---- 2. dashboard before check-in -----------------------------------
        att = self.client.get("/api/attendance/").data
        keys(self, att, "checked_in", "checked_out", "check_in", "check_out", "worked_seconds")
        self.assertFalse(att["checked_in"])
        active = self.client.get("/api/time-tracking/active/").data
        self.assertIsNone(active["entry"])

        # timer cannot start before check-in
        res = self.client.post("/api/time-tracking/", {"action": "start", "task": self.t1.id}, format="json")
        self.assertEqual(res.status_code, 400)
        self.assertIn("check in", res.data["detail"].lower())

        # ---- 3. check in -----------------------------------------------------
        self.assertEqual(self.client.post("/api/attendance/", {"action": "check_in"}, format="json").status_code, 200)
        att = self.client.get("/api/attendance/").data
        self.assertTrue(att["checked_in"]); self.assertFalse(att["checked_out"])
        self.assertIsNotNone(att["check_in"])
        again = self.client.post("/api/attendance/", {"action": "check_in"}, format="json")
        self.assertEqual(again.status_code, 400)                       # shown via snackbar

        # ---- 4. tasks: only mine, with every field the cards read ----------
        tasks = self.client.get("/api/tasks/").data
        self.assertEqual({t["title"] for t in tasks}, {"Build login", "Write docs"})
        for t in tasks:
            keys(self, t, "id", "title", "description", "status", "priority", "due_date",
                 "project", "project_name", "created_at", "completed_at")
        # the app no longer needs ?assigned_to, but the old TodayTab sends it: must still work
        self.assertEqual(len(self.client.get("/api/tasks/", {"assigned_to": self.emp.id}).data), 2)
        self.assertEqual(len(self.client.get("/api/tasks/", {"project": self.proj.id}).data), 2)
        self.assertEqual(self.client.get(f"/api/tasks/{self.rival_task.id}/").status_code, 404)

        # ---- 5. projects: only mine, with every field the cards/detail read
        projects = self.client.get("/api/projects/").data
        self.assertEqual([p["name"] for p in projects], ["Website"])
        keys(self, projects[0], "id", "name", "description", "status", "priority", "client_name",
             "project_manager_name", "start_date", "deadline", "progress_percent", "completed_tasks",
             "total_tasks", "tracked_seconds", "is_overdue", "team_members_detail")
        self.assertEqual(self.client.get(f"/api/projects/{self.other_proj.id}/").status_code, 404)
        detail = self.client.get(f"/api/projects/{self.proj.id}/").data
        self.assertEqual({m["username"] for m in detail["team_members_detail"]}, {"priya", "rival"})
        self.assertEqual(self.client.patch(f"/api/projects/{self.proj.id}/", {"status": "COMPLETED"}, format="json").status_code, 403)

        # ---- 6. status rules the UI mirrors ----------------------------------
        bad = self.client.patch(f"/api/tasks/{self.t1.id}/", {"status": "COMPLETED"}, format="json")
        self.assertEqual(bad.status_code, 400)                          # TODO -> COMPLETED not allowed
        self.assertEqual(self.client.patch(f"/api/tasks/{self.t1.id}/", {"title": "Hacked"}, format="json").status_code, 403)
        self.assertEqual(self.client.patch(f"/api/tasks/{self.rival_task.id}/", {"status": "IN_PROGRESS"}, format="json").status_code, 404)

        # ---- 7. timer: start / pause / resume / stop --------------------------
        res = self.client.post("/api/time-tracking/", {"action": "start", "task": self.t1.id}, format="json")
        self.assertEqual(res.status_code, 201)
        entry = self.client.get("/api/time-tracking/active/").data["entry"]
        keys(self, entry, "id", "task", "task_title", "status", "elapsed_seconds")
        self.assertEqual((entry["status"], entry["task"], entry["task_title"]), ("RUNNING", self.t1.id, "Build login"))
        self.assertEqual(Task.objects.get(pk=self.t1.id).status, "IN_PROGRESS")   # auto TODO -> IN_PROGRESS

        # one timer at a time
        second = self.client.post("/api/time-tracking/", {"action": "start", "task": self.t2.id}, format="json")
        self.assertEqual(second.status_code, 400)
        # not allowed to time someone else's task
        self.assertEqual(self.client.post("/api/time-tracking/", {"action": "start", "task": self.rival_task.id}, format="json").status_code, 403)

        self.assertEqual(self.client.post("/api/time-tracking/", {"action": "pause"}, format="json").status_code, 200)
        self.assertEqual(self.client.get("/api/time-tracking/active/").data["entry"]["status"], "PAUSED")
        self.assertEqual(self.client.post("/api/time-tracking/", {"action": "resume"}, format="json").status_code, 200)
        self.assertEqual(self.client.get("/api/time-tracking/active/").data["entry"]["status"], "RUNNING")

        # ---- 8. complete the task WHILE its timer runs (app: stop, then PATCH)
        self.assertEqual(self.client.post("/api/time-tracking/", {"action": "stop"}, format="json").status_code, 200)
        self.assertIsNone(self.client.get("/api/time-tracking/active/").data["entry"])
        ok = self.client.patch(f"/api/tasks/{self.t1.id}/", {"status": "COMPLETED"}, format="json")
        self.assertEqual(ok.status_code, 200, ok.data)
        self.assertIsNotNone(ok.data["completed_at"])
        # completed task can't be timed; can be reopened
        self.assertEqual(self.client.post("/api/time-tracking/", {"action": "start", "task": self.t1.id}, format="json").status_code, 400)
        self.assertEqual(self.client.patch(f"/api/tasks/{self.t1.id}/", {"status": "IN_PROGRESS"}, format="json").status_code, 200)

        # per-task + today's tracked time (Task detail / Dashboard)
        mine = self.client.get("/api/time-tracking/", {"task": self.t1.id}).data
        self.assertEqual(len(mine), 1)
        keys(self, mine[0], "elapsed_seconds", "status", "task", "date", "started_at", "ended_at")
        self.assertEqual(mine[0]["status"], "STOPPED")
        today_entries = self.client.get("/api/time-tracking/", {"date_from": str(timezone.localdate())}).data
        self.assertEqual(len(today_entries), 1)

        # leave a timer running, then check out: it must be stopped by the server
        self.client.post("/api/time-tracking/", {"action": "start", "task": self.t2.id}, format="json")
        co = self.client.post("/api/attendance/", {"action": "check_out"}, format="json")
        self.assertEqual(co.status_code, 200)
        self.assertIsNone(self.client.get("/api/time-tracking/active/").data["entry"])
        att = self.client.get("/api/attendance/").data
        self.assertTrue(att["checked_out"])

        # ---- 9. attendance history -----------------------------------------
        hist = self.client.get("/api/attendance/history/", {
            "date_from": str(timezone.localdate() - timedelta(days=29)),
            "date_to": str(timezone.localdate())}).data
        self.assertEqual(len(hist), 1)
        keys(self, hist[0], "id", "date", "check_in", "check_out", "status", "worked_seconds")
        self.assertIsNotNone(hist[0]["check_out"])

        # ---- 10. expenses --------------------------------------------------
        body = {"title": "Client lunch", "amount": "1250", "category": "FOOD", "payment_method": "UPI",
                "date": str(timezone.localdate()), "project": self.proj.id}   # exactly what the form sends
        res = self.client.post("/api/expenses/claims/", body, format="json")
        self.assertEqual(res.status_code, 201, res.data)
        claims = self.client.get("/api/expenses/claims/").data
        keys(self, claims[0], "id", "title", "amount", "category", "date", "notes", "project_name",
             "status", "review_note", "created_at")
        self.assertEqual(claims[0]["status"], "PENDING")
        # blank notes/None project, as the form may send
        res = self.client.post("/api/expenses/claims/", {"title": "Pen", "amount": "20", "category": "SUPPLIES",
                               "payment_method": "CASH", "notes": "", "project": None}, format="json")
        self.assertEqual(res.status_code, 201, res.data)

        # ---- 11. notifications ----------------------------------------------
        feed = self.client.get("/api/notifications/").data
        self.assertTrue(feed, "assigning tasks/adding to project should have produced notifications")
        keys(self, feed[0], "id", "kind", "title", "message", "is_read", "created_at")
        before = self.client.get("/api/notifications/unread-count/").data["count"]
        self.assertGreater(before, 0)
        self.client.post(f"/api/notifications/{feed[0]['id']}/read/")
        self.assertEqual(self.client.get("/api/notifications/unread-count/").data["count"], before - 1)
        self.client.post("/api/notifications/read-all/")
        self.assertEqual(self.client.get("/api/notifications/unread-count/").data["count"], 0)

        # ---- 12. employee can't reach admin-only data -------------------------
        for path in ("/api/reports/dashboard/", "/api/attendance/manage/", "/api/auth/employees/",
                     "/api/expenses/", "/api/expenses/summary/"):
            self.assertEqual(self.client.get(path).status_code, 403, path)

        # ---- 13. logout kills the token ---------------------------------------
        self.assertEqual(self.client.post("/api/auth/logout/").status_code, 200)
        self.assertEqual(self.client.get("/api/tasks/").status_code, 401)

    def test_manager_my_day_still_works_with_old_calls(self):
        """HR/Manager 'My Day' (old TodayTab/TimeLogTab) uses these exact calls."""
        self.login("mgr")
        self.assertEqual(self.client.get("/api/attendance/").status_code, 200)
        self.assertEqual(self.client.get("/api/time-tracking/active/").status_code, 200)
        self.assertEqual(self.client.get("/api/tasks/", {"assigned_to": self.mgr.id}).status_code, 200)
        self.assertEqual(self.client.get("/api/time-tracking/", {"date_from": str(timezone.localdate() - timedelta(days=6))}).status_code, 200)
