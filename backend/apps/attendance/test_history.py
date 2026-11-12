from datetime import timedelta

from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from .models import Attendance


class AttendanceHistoryTests(APITestCase):
    def setUp(self):
        self.emp = User.objects.create_user("emp", password="pass12345")
        self.other = User.objects.create_user("other", password="pass12345")
        self.today = timezone.localdate()
        now = timezone.now()

        def rec(user, days_ago, hours=8, status="PRESENT"):
            d = self.today - timedelta(days=days_ago)
            ci = now - timedelta(days=days_ago, hours=hours)
            co = ci + timedelta(hours=hours) if hours else None
            return Attendance.objects.create(
                user=user, date=d, check_in=ci, check_out=co, status=status
            )

        self.r0 = rec(self.emp, 0, hours=0)      # today, still working
        self.r1 = rec(self.emp, 1, hours=8)
        self.r5 = rec(self.emp, 5, hours=4, status="HALF_DAY")
        self.r40 = rec(self.emp, 40, hours=8)    # outside the default 30 days
        rec(self.other, 1)                       # somebody else's record

        token, _ = Token.objects.get_or_create(user=self.emp)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def test_requires_login(self):
        self.client.credentials()
        self.assertEqual(self.client.get("/api/attendance/history/").status_code, 401)

    def test_returns_only_my_records_newest_first_default_30_days(self):
        res = self.client.get("/api/attendance/history/")
        self.assertEqual(res.status_code, 200)
        self.assertEqual([r["id"] for r in res.data], [self.r0.id, self.r1.id, self.r5.id])
        self.assertTrue(all(r["username"] == "emp" for r in res.data))

    def test_row_has_everything_the_app_shows(self):
        row = next(r for r in self.client.get("/api/attendance/history/").data if r["id"] == self.r1.id)
        for key in ("date", "check_in", "check_out", "status", "worked_seconds"):
            self.assertIn(key, row)
        self.assertEqual(row["worked_seconds"], 8 * 3600)
        self.assertEqual(row["status"], "PRESENT")

    def test_open_day_has_no_check_out_and_zero_worked(self):
        row = next(r for r in self.client.get("/api/attendance/history/").data if r["id"] == self.r0.id)
        self.assertIsNone(row["check_out"])
        self.assertEqual(row["worked_seconds"], 0)

    def test_date_range_filter(self):
        start = str(self.today - timedelta(days=45))
        res = self.client.get("/api/attendance/history/", {"date_from": start})
        self.assertIn(self.r40.id, [r["id"] for r in res.data])

        one_day = str(self.today - timedelta(days=1))
        res = self.client.get("/api/attendance/history/", {"date_from": one_day, "date_to": one_day})
        self.assertEqual([r["id"] for r in res.data], [self.r1.id])

    def test_bad_dates_are_400_not_500(self):
        for params in ({"date_from": "yesterday"}, {"date_to": "2026-13-45"},
                       {"date_from": "2026-11-10", "date_to": "2026-11-01"}):
            self.assertEqual(
                self.client.get("/api/attendance/history/", params).status_code, 400, params
            )

    def test_existing_today_endpoint_unchanged(self):
        res = self.client.get("/api/attendance/")
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data["checked_in"])
        self.assertFalse(res.data["checked_out"])
