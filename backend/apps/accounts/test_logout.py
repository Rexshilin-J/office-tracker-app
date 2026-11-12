from django.contrib.auth.models import User
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase


class LogoutTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user("emp", password="pass12345")

    def login(self):
        res = self.client.post(
            "/api/auth/login/", {"username": "emp", "password": "pass12345"}, format="json"
        )
        self.assertEqual(res.status_code, 200)
        return res.data["token"]

    def test_logout_revokes_the_token(self):
        token = self.login()
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token}")
        self.assertEqual(self.client.get("/api/auth/me/").status_code, 200)

        self.assertEqual(self.client.post("/api/auth/logout/").status_code, 200)

        # the very same token must now be rejected everywhere
        self.assertEqual(self.client.get("/api/auth/me/").status_code, 401)
        self.assertFalse(Token.objects.filter(user=self.user).exists())

    def test_logout_needs_a_valid_token(self):
        self.assertEqual(self.client.post("/api/auth/logout/").status_code, 401)

    def test_can_log_in_again_after_logout(self):
        token = self.login()
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token}")
        self.client.post("/api/auth/logout/")
        self.client.credentials()
        new_token = self.login()
        self.assertNotEqual(token, new_token)
