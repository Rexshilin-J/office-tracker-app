from datetime import timedelta
from unittest import mock

from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.projects.models import Project
from apps.tasks.models import Task

from .models import Announcement, Notification


class Base(APITestCase):
    def setUp(self):
        self.emp = User.objects.create_user("emp", password="pass12345")
        self.emp2 = User.objects.create_user("emp2", password="pass12345")
        self.mgr = User.objects.create_user("mgr", password="pass12345")
        self.project = Project.objects.create(name="Website", project_manager=self.mgr, created_by=self.mgr)
        self.project.team_members.add(self.emp, self.emp2)
        Notification.objects.all().delete()  # ignore "added to project" noise from setUp

    def as_user(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def mk_task(self, **kw):
        data = dict(project=self.project, title="Fix login", created_by=self.mgr, assigned_to=self.emp)
        data.update(kw)
        return Task.objects.create(**data)


class SignalTests(Base):
    def test_new_assigned_task_notifies_assignee_only(self):
        due = timezone.localdate() + timedelta(days=3)
        t = self.mk_task(due_date=due)
        n = Notification.objects.get()
        self.assertEqual((n.recipient, n.kind, n.title), (self.emp, "TASK", "New task assigned"))
        self.assertIn("Fix login", n.message)
        self.assertIn("Website", n.message)
        self.assertIn("due", n.message)
        self.assertEqual((n.task, n.project, n.is_read), (t, self.project, False))

    def test_unassigned_task_notifies_nobody(self):
        self.mk_task(assigned_to=None)
        self.assertEqual(Notification.objects.count(), 0)

    def test_assigning_a_task_to_yourself_is_silent(self):
        self.mk_task(created_by=self.emp, assigned_to=self.emp)
        self.assertEqual(Notification.objects.count(), 0)

    def test_reassigning_notifies_the_new_person_once(self):
        t = self.mk_task()
        Notification.objects.all().delete()
        t.assigned_to = self.emp2
        t.save()
        self.assertEqual(list(Notification.objects.values_list("recipient__username", flat=True)), ["emp2"])

    def test_ordinary_edits_and_status_changes_do_not_notify(self):
        t = self.mk_task()
        Notification.objects.all().delete()
        t.status = "IN_PROGRESS"
        t.save()
        t.save(update_fields=["status", "updated_at"])   # what the timer does
        t.title = "Renamed"
        t.save()
        self.assertEqual(Notification.objects.count(), 0)

    def test_added_to_project(self):
        newbie = User.objects.create_user("newbie", password="pass12345")
        self.project.team_members.add(newbie)
        n = Notification.objects.get()
        self.assertEqual((n.recipient, n.kind, n.title), (newbie, "PROJECT", "You were added to a project"))
        self.assertEqual(n.message, "Website")

    def test_project_creator_is_not_told_they_joined_their_own_project(self):
        p = Project.objects.create(name="Mine", created_by=self.mgr)
        p.team_members.add(self.mgr, self.emp)
        self.assertEqual(list(Notification.objects.values_list("recipient__username", flat=True)), ["emp"])

    def test_project_status_and_deadline_change_notify_team_and_manager(self):
        self.project.status = "ON_HOLD"
        self.project.deadline = timezone.localdate() + timedelta(days=10)
        self.project.save()
        who = set(Notification.objects.values_list("recipient__username", flat=True))
        self.assertEqual(who, {"emp", "emp2", "mgr"})
        n = Notification.objects.filter(recipient=self.emp).get()
        self.assertEqual(n.title, "Project updated: Website")
        self.assertIn("Status: Planning -> On Hold", n.message)
        self.assertIn("Deadline: none ->", n.message)

    def test_unrelated_project_edit_does_not_notify(self):
        self.project.description = "new text"
        self.project.save()
        self.assertEqual(Notification.objects.count(), 0)

    def test_announcement_reaches_every_active_user_but_not_inactive(self):
        User.objects.create_user("gone", password="pass12345", is_active=False)
        Announcement.objects.create(title="Office closed Friday", message="Diwali holiday", created_by=self.mgr)
        got = set(Notification.objects.filter(kind="ANNOUNCEMENT").values_list("recipient__username", flat=True))
        self.assertEqual(got, {"emp", "emp2", "mgr"})
        self.assertEqual(Notification.objects.filter(recipient=self.emp).get().message, "Diwali holiday")

    def test_editing_an_announcement_does_not_resend(self):
        a = Announcement.objects.create(title="Hi", message="x")
        count = Notification.objects.count()
        a.message = "y"
        a.save()
        self.assertEqual(Notification.objects.count(), count)

    def test_a_notification_failure_never_breaks_the_original_save(self):
        with mock.patch("apps.notifications.signals.Notification.objects.bulk_create", side_effect=RuntimeError("db down")):
            with self.assertLogs("apps.notifications.signals", level="ERROR"):
                t = self.mk_task()
        self.assertTrue(Task.objects.filter(pk=t.pk).exists())


class AdminFlowStillWorks(Base):
    """The Admin app creates/edits through the API - make sure that is unaffected."""

    def setUp(self):
        super().setUp()
        from apps.accounts.models import EmployeeProfile

        EmployeeProfile.objects.create(user=self.mgr, employee_id="M1", role="MANAGER")
        self.as_user(self.mgr)

    def test_manager_creates_a_task_via_api_and_assignee_is_notified(self):
        res = self.client.post(
            "/api/tasks/",
            {"project": self.project.id, "title": "API task", "assigned_to": self.emp.id},
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.data)
        self.assertEqual(Notification.objects.filter(recipient=self.emp, kind="TASK").count(), 1)

    def test_manager_edits_a_project_via_api_and_team_is_notified(self):
        res = self.client.patch(
            f"/api/projects/{self.project.id}/", {"status": "IN_PROGRESS"}, format="json"
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(Notification.objects.filter(recipient=self.emp, kind="PROJECT").count(), 1)

    def test_employee_status_change_on_own_task_still_works_and_is_silent(self):
        t = self.mk_task()
        Notification.objects.all().delete()
        self.as_user(self.emp)
        res = self.client.patch(f"/api/tasks/{t.id}/", {"status": "IN_PROGRESS"}, format="json")
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(Notification.objects.count(), 0)


class EndpointTests(Base):
    def setUp(self):
        super().setUp()
        self.t = self.mk_task()                     # -> emp gets 1 TASK notification
        Announcement.objects.create(title="Notice", message="m")  # -> everybody 1 more
        self.as_user(self.emp)

    def test_requires_login(self):
        self.client.credentials()
        for path in ("/api/notifications/", "/api/notifications/unread-count/"):
            self.assertEqual(self.client.get(path).status_code, 401)
        self.assertEqual(self.client.post("/api/notifications/read-all/").status_code, 401)

    def test_list_is_mine_only_newest_first_with_expected_fields(self):
        res = self.client.get("/api/notifications/")
        self.assertEqual(res.status_code, 200)
        self.assertEqual([n["title"] for n in res.data], ["Notice", "New task assigned"])
        for key in ("id", "kind", "title", "message", "task", "project", "is_read", "created_at"):
            self.assertIn(key, res.data[0])
        self.assertEqual(res.data[1]["task"], self.t.id)

    def test_unread_count_and_filter(self):
        self.assertEqual(self.client.get("/api/notifications/unread-count/").data, {"count": 2})
        first = Notification.objects.filter(recipient=self.emp).first()
        self.client.post(f"/api/notifications/{first.id}/read/")
        self.assertEqual(self.client.get("/api/notifications/unread-count/").data, {"count": 1})
        unread = self.client.get("/api/notifications/", {"unread": "1"})
        self.assertEqual(len(unread.data), 1)
        self.assertFalse(unread.data[0]["is_read"])

    def test_mark_one_read_is_idempotent(self):
        n = Notification.objects.filter(recipient=self.emp).first()
        for _ in range(2):
            res = self.client.post(f"/api/notifications/{n.id}/read/")
            self.assertEqual(res.status_code, 200)
            self.assertTrue(res.data["is_read"])

    def test_cannot_read_or_touch_someone_elses(self):
        theirs = Notification.objects.filter(recipient=self.emp2).first()
        self.assertEqual(self.client.post(f"/api/notifications/{theirs.id}/read/").status_code, 404)
        theirs.refresh_from_db()
        self.assertFalse(theirs.is_read)

    def test_read_all_only_affects_me(self):
        res = self.client.post("/api/notifications/read-all/")
        self.assertEqual(res.data, {"updated": 2})
        self.assertEqual(self.client.get("/api/notifications/unread-count/").data, {"count": 0})
        self.assertEqual(Notification.objects.filter(recipient=self.emp2, is_read=False).count(), 1)

    def test_list_is_capped_at_100(self):
        Notification.objects.bulk_create(
            [Notification(recipient=self.emp, kind="TASK", title=f"n{i}") for i in range(120)]
        )
        self.assertEqual(len(self.client.get("/api/notifications/").data), 100)
