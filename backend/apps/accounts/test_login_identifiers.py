from django.contrib.auth.models import User
from rest_framework.test import APIClient, APITestCase

from .models import EmployeeProfile


class LoginIdentifierTests(APITestCase):
    """An account created by the Admin must be able to log in right away."""

    def setUp(self):
        self.boss = User.objects.create_superuser("boss", "b@x.com", "bosspass123")
        admin = APIClient()
        admin.force_authenticate(self.boss)
        res = admin.post(
            "/api/auth/register/",
            {"username": "Priya", "email": "Priya@Example.com", "password": "Secret@123",
             "employee_id": "EMP001", "role": "EMPLOYEE"},
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.data)

    def login(self, who, password="Secret@123"):
        return self.client.post("/api/auth/login/", {"username": who, "password": password}, format="json")

    def test_every_way_an_employee_might_type_it(self):
        for who in ("Priya", "priya", "PRIYA", " Priya ", "EMP001", "emp001", "Emp001 ",
                    "priya@example.com", "Priya@Example.com"):
            res = self.login(who)
            self.assertEqual(res.status_code, 200, who)
            self.assertEqual(res.data["user"]["username"], "Priya", who)
            self.assertEqual(res.data["user"]["employee_id"], "EMP001")

    def test_wrong_password_or_unknown_id_is_refused_with_same_message(self):
        a = self.login("EMP001", "wrongpass1")
        b = self.login("EMP999")
        c = self.login("")
        for r in (a, b, c):
            self.assertEqual(r.status_code, 400)
        self.assertEqual(a.data, b.data)

    def test_deactivated_account_cannot_log_in_by_employee_id(self):
        User.objects.filter(username="Priya").update(is_active=False)
        self.assertEqual(self.login("EMP001").status_code, 400)

    def test_exact_username_wins_over_someone_elses_employee_id(self):
        other = User.objects.create_user("EMP001", password="Other@1234")
        EmployeeProfile.objects.create(user=other, employee_id="X9")
        res = self.login("EMP001", "Other@1234")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data["user"]["username"], "EMP001")
        # ...and Priya's password does not open that account
        self.assertEqual(self.login("EMP001", "Secret@123").status_code, 400)

    def test_ambiguous_identifier_is_refused_not_guessed(self):
        User.objects.create_user("priya", password="Secret@123")   # differs only by case
        self.assertEqual(self.login("PRIYA").status_code, 400)     # two matches -> refuse
        self.assertEqual(self.login("Priya").status_code, 200)     # exact still works
        self.assertEqual(self.login("priya").status_code, 200)

    def test_password_is_still_case_sensitive(self):
        self.assertEqual(self.login("EMP001", "secret@123").status_code, 400)
