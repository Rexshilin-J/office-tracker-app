from django.test import TestCase

# Create your tests here.


from django.contrib.auth.models import User as _U
from rest_framework.authtoken.models import Token as _T
from rest_framework.test import APITestCase as _A


class AttendanceStatusTests(_A):
    def test_status_flow(self):
        user = _U.objects.create_user("emp", password="pass12345")
        token, _ = _T.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        self.assertFalse(self.client.get("/api/attendance/").data["checked_in"])
        self.client.post("/api/attendance/", {"action": "check_in"}, format="json")
        data = self.client.get("/api/attendance/").data
        self.assertTrue(data["checked_in"])
        self.assertFalse(data["checked_out"])
        self.client.post("/api/attendance/", {"action": "check_out"}, format="json")
        self.assertTrue(self.client.get("/api/attendance/").data["checked_out"])
