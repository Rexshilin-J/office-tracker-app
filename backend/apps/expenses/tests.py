from django.contrib.auth.models import User
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase


class ExpenseTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_superuser("boss", password="pass12345")
        self.emp = User.objects.create_user("emp", password="pass12345")

    def auth(self, user):
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def test_employee_blocked(self):
        self.auth(self.emp)
        self.assertEqual(self.client.get("/api/expenses/").status_code, 403)
        res = self.client.post("/api/expenses/", {"title": "x", "amount": "5"})
        self.assertEqual(res.status_code, 403)

    def test_admin_crud_and_summary(self):
        self.auth(self.admin)
        res = self.client.post(
            "/api/expenses/",
            {"title": "Office rent", "amount": "25000", "category": "RENT"},
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.data)
        eid = res.data["id"]
        self.assertEqual(res.data["created_by_name"], "boss")

        self.client.post(
            "/api/expenses/",
            {"title": "Tea", "amount": "120.50", "category": "FOOD"},
            format="json",
        )

        bad = self.client.post("/api/expenses/", {"title": "Bad", "amount": "0"})
        self.assertEqual(bad.status_code, 400)

        self.assertEqual(len(self.client.get("/api/expenses/").data), 2)
        self.assertEqual(len(self.client.get("/api/expenses/?category=FOOD").data), 1)

        s = self.client.get("/api/expenses/summary/").data
        self.assertEqual(s["count"], 2)
        self.assertAlmostEqual(s["total"], 25120.5)
        self.assertAlmostEqual(s["this_month_total"], 25120.5)
        self.assertEqual(len(s["monthly"]), 6)
        self.assertEqual(s["by_category"][0]["category"], "RENT")

        res = self.client.patch(f"/api/expenses/{eid}/", {"amount": "26000"}, format="json")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(self.client.delete(f"/api/expenses/{eid}/").status_code, 204)

    def test_me_exposes_capability(self):
        self.auth(self.admin)
        self.assertTrue(self.client.get("/api/auth/me/").data["capabilities"]["manage_expenses"])
        self.auth(self.emp)
        self.assertFalse(self.client.get("/api/auth/me/").data["capabilities"]["manage_expenses"])
