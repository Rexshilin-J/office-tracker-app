from django.test import TestCase

# Create your tests here.


from django.contrib.auth.models import User as _User
from django.test import override_settings
from rest_framework.authtoken.models import Token as _Token
from rest_framework.test import APITestCase as _APITestCase


class MeAndEmployeesTests(_APITestCase):
    def setUp(self):
        self.admin = _User.objects.create_user("admin", password="pass12345", is_staff=True)
        self.emp = _User.objects.create_user("emp", password="pass12345")

    def auth(self, user):
        token, _ = _Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def test_me(self):
        self.auth(self.emp)
        res = self.client.get("/api/auth/me/")
        self.assertEqual(res.data["username"], "emp")
        self.assertEqual(res.data["role"], "EMPLOYEE")

    def test_employee_list_admin_only(self):
        self.auth(self.emp)
        self.assertEqual(self.client.get("/api/auth/employees/").status_code, 403)
        self.auth(self.admin)
        self.assertEqual(len(self.client.get("/api/auth/employees/").data), 2)

    @override_settings(DEBUG=True)
    def test_cors_preflight_allowed_in_debug(self):
        res = self.client.options("/api/tasks/", HTTP_ORIGIN="http://localhost:5555")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res["Access-Control-Allow-Origin"], "http://localhost:5555")
