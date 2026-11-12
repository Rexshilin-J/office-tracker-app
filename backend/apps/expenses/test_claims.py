from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.models import User
from django.test import TestCase
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.projects.models import Project

from .models import Expense, ExpenseClaim


class ClaimAPITests(APITestCase):
    def setUp(self):
        self.emp = User.objects.create_user("emp", password="pass12345")
        self.other = User.objects.create_user("other", password="pass12345")
        self.admin = User.objects.create_user("boss", password="pass12345", is_staff=True)
        self.mine = Project.objects.create(name="Mine")
        self.mine.team_members.add(self.emp)
        self.not_mine = Project.objects.create(name="Secret")
        self.as_user(self.emp)

    def as_user(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def payload(self, **kw):
        data = {"title": "Cab to client", "amount": "450.50", "category": "TRAVEL",
                "payment_method": "UPI", "notes": "Airport run"}
        data.update(kw)
        return data

    # ---- submit -----------------------------------------------------------
    def test_employee_can_submit_and_it_starts_pending(self):
        res = self.client.post("/api/expenses/claims/", self.payload(project=self.mine.id), format="json")
        self.assertEqual(res.status_code, 201, res.data)
        self.assertEqual(res.data["status"], "PENDING")
        self.assertEqual(res.data["status_label"], "Pending")
        self.assertEqual(res.data["project_name"], "Mine")
        self.assertEqual(res.data["category_label"], "Travel")
        claim = ExpenseClaim.objects.get()
        self.assertEqual(claim.submitted_by, self.emp)
        self.assertEqual(claim.amount, Decimal("450.50"))

    def test_cannot_self_approve_or_spoof_owner(self):
        res = self.client.post(
            "/api/expenses/claims/",
            self.payload(status="APPROVED", review_note="ok", submitted_by=self.other.id),
            format="json",
        )
        self.assertEqual(res.status_code, 201)
        claim = ExpenseClaim.objects.get()
        self.assertEqual(claim.status, "PENDING")
        self.assertEqual(claim.review_note, "")
        self.assertEqual(claim.submitted_by, self.emp)

    def test_validation(self):
        for bad, key in (
            ({"title": "   "}, "title"),
            ({"amount": "0"}, "amount"),
            ({"amount": "-5"}, "amount"),
            ({"amount": "abc"}, "amount"),
            ({"category": "YACHT"}, "category"),
            ({"date": str(timezone.localdate() + timedelta(days=3))}, "date"),
            ({"project": self.not_mine.id}, "project"),
        ):
            res = self.client.post("/api/expenses/claims/", self.payload(**bad), format="json")
            self.assertEqual(res.status_code, 400, bad)
            self.assertIn(key, res.data, bad)
        self.assertEqual(ExpenseClaim.objects.count(), 0)

    def test_project_is_optional(self):
        res = self.client.post("/api/expenses/claims/", self.payload(), format="json")
        self.assertEqual(res.status_code, 201)
        self.assertIsNone(res.data["project"])

    # ---- history / scoping --------------------------------------------------
    def test_i_only_see_my_own_claims_with_status_filter(self):
        a = ExpenseClaim.objects.create(title="A", amount=10, submitted_by=self.emp)
        b = ExpenseClaim.objects.create(title="B", amount=20, submitted_by=self.emp, status="APPROVED")
        ExpenseClaim.objects.create(title="NotMine", amount=30, submitted_by=self.other)

        res = self.client.get("/api/expenses/claims/")
        self.assertEqual({r["title"] for r in res.data}, {"A", "B"})
        res = self.client.get("/api/expenses/claims/", {"status": "APPROVED"})
        self.assertEqual([r["id"] for r in res.data], [b.id])
        self.assertEqual(self.client.get(f"/api/expenses/claims/{a.id}/").status_code, 200)

    def test_cannot_open_someone_elses_claim(self):
        theirs = ExpenseClaim.objects.create(title="X", amount=1, submitted_by=self.other)
        self.assertEqual(self.client.get(f"/api/expenses/claims/{theirs.id}/").status_code, 404)

    def test_requires_login(self):
        self.client.credentials()
        self.assertEqual(self.client.get("/api/expenses/claims/").status_code, 401)
        self.assertEqual(self.client.post("/api/expenses/claims/", self.payload(), format="json").status_code, 401)

    def test_claims_are_read_only_after_submit(self):
        c = ExpenseClaim.objects.create(title="A", amount=10, submitted_by=self.emp)
        for method in (self.client.patch, self.client.put, self.client.delete):
            self.assertEqual(method(f"/api/expenses/claims/{c.id}/", {"status": "APPROVED"}, format="json").status_code, 405)
        c.refresh_from_db()
        self.assertEqual(c.status, "PENDING")

    # ---- the Admin screen must be untouched --------------------------------
    def test_employee_still_cannot_use_the_company_ledger(self):
        for path in ("/api/expenses/", "/api/expenses/summary/"):
            self.assertEqual(self.client.get(path).status_code, 403, path)
        self.assertEqual(self.client.post("/api/expenses/", self.payload(), format="json").status_code, 403)

    def test_claims_never_change_admin_ledger_or_totals(self):
        Expense.objects.create(title="Rent", amount=1000, category="RENT", created_by=self.admin)
        self.client.post("/api/expenses/claims/", self.payload(), format="json")
        ExpenseClaim.objects.create(title="Big", amount=99999, submitted_by=self.emp, status="APPROVED")

        self.as_user(self.admin)
        ledger = self.client.get("/api/expenses/")
        self.assertEqual([e["title"] for e in ledger.data], ["Rent"])
        summary = self.client.get("/api/expenses/summary/")
        self.assertEqual(summary.data["total"], 1000.0)
        self.assertEqual(summary.data["count"], 1)


class ClaimReviewTests(TestCase):
    def setUp(self):
        self.emp = User.objects.create_user("emp", password="x12345678")
        self.boss = User.objects.create_superuser("boss", "b@x.com", "x12345678")
        self.claim = ExpenseClaim.objects.create(title="Lunch", amount=250, submitted_by=self.emp)

    def test_approve_stamps_reviewer(self):
        self.claim.review(self.boss, "APPROVED", "Thanks")
        self.claim.refresh_from_db()
        self.assertEqual(self.claim.status, "APPROVED")
        self.assertEqual(self.claim.reviewed_by, self.boss)
        self.assertIsNotNone(self.claim.reviewed_at)
        self.assertEqual(self.claim.review_note, "Thanks")

    def test_reject_needs_a_reason(self):
        with self.assertRaises(Exception):
            self.claim.review(self.boss, "REJECTED", "  ")
        self.claim.refresh_from_db()
        self.assertEqual(self.claim.status, "PENDING")

    def test_reject_with_reason(self):
        self.claim.review(self.boss, "REJECTED", "No receipt")
        self.claim.refresh_from_db()
        self.assertEqual((self.claim.status, self.claim.review_note), ("REJECTED", "No receipt"))

    def test_cannot_review_twice_or_with_bad_status(self):
        self.claim.review(self.boss, "APPROVED")
        with self.assertRaises(ValueError):
            self.claim.review(self.boss, "REJECTED", "changed my mind")
        fresh = ExpenseClaim.objects.create(title="Y", amount=1, submitted_by=self.emp)
        with self.assertRaises(ValueError):
            fresh.review(self.boss, "PENDING")

    def test_employee_sees_the_decision_through_the_api(self):
        self.claim.review(self.boss, "REJECTED", "No receipt")
        token = Token.objects.create(user=self.emp)
        res = self.client.get("/api/expenses/claims/", HTTP_AUTHORIZATION=f"Token {token.key}")
        row = res.json()[0]
        self.assertEqual(row["status"], "REJECTED")
        self.assertEqual(row["review_note"], "No receipt")
        self.assertEqual(row["reviewed_by_name"], "boss")

    def test_django_admin_approve_action_and_edit_form(self):
        self.client.force_login(self.boss)
        # bulk action
        res = self.client.post(
            "/admin/expenses/expenseclaim/",
            {"action": "approve_selected", "_selected_action": [self.claim.id]},
            follow=True,
        )
        self.assertEqual(res.status_code, 200)
        self.claim.refresh_from_db()
        self.assertEqual((self.claim.status, self.claim.reviewed_by), ("APPROVED", self.boss))

        # rejecting through the change form stamps the reviewer too
        other = ExpenseClaim.objects.create(title="Taxi", amount=80, submitted_by=self.emp)
        res = self.client.post(
            f"/admin/expenses/expenseclaim/{other.id}/change/",
            {"title": "Taxi", "amount": "80.00", "category": "OTHER", "payment_method": "CASH",
             "date": str(timezone.localdate()), "notes": "", "status": "REJECTED",
             "review_note": "Not a business trip"},
        )
        self.assertEqual(res.status_code, 302, getattr(res, "context", None) and res.context["errors"])
        other.refresh_from_db()
        self.assertEqual((other.status, other.reviewed_by), ("REJECTED", self.boss))
        self.assertIsNotNone(other.reviewed_at)
