
from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Attendance


class AttendanceAPIView(APIView):
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """Today's attendance status for the logged-in user."""
        today = timezone.localdate()
        record = Attendance.objects.filter(user=request.user, date=today).first()
        return Response(
            {
                "date": str(today),
                "checked_in": bool(record and record.check_in),
                "checked_out": bool(record and record.check_out),
                "check_in": record.check_in if record else None,
                "check_out": record.check_out if record else None,
                "worked_seconds": record.worked_seconds if record else 0,
            }
        )

    def post(self, request):
        action = request.data.get("action")

        today = timezone.localdate()

        if action == "check_in":
            attendance, created = Attendance.objects.get_or_create(
                user=request.user,
                date=today,
                defaults={
                    "check_in": timezone.now(),
                    "status": "PRESENT",
                },
            )

            if not created:
                if attendance.check_in:
                    return Response(
                        {"detail": "You have already checked in today."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )

                attendance.check_in = timezone.now()
                attendance.status = "PRESENT"
                attendance.save(update_fields=["check_in", "status"])

            return Response(
                {
                    "message": "Check-in successful.",
                    "username": request.user.username,
                    "date": str(attendance.date),
                    "check_in": attendance.check_in,
                },
                status=status.HTTP_200_OK,
            )

        if action == "check_out":
            try:
                attendance = Attendance.objects.get(
                    user=request.user,
                    date=today,
                )
            except Attendance.DoesNotExist:
                return Response(
                    {"detail": "Please check in before checking out."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if not attendance.check_in:
                return Response(
                    {"detail": "Please check in before checking out."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if attendance.check_out:
                return Response(
                    {"detail": "You have already checked out today."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            from apps.time_tracking.services import stop_active_timer_for

            now = timezone.now()
            with transaction.atomic():
                # Do not leave a timer running after the workday ends.
                stop_active_timer_for(request.user, now)
                attendance.check_out = now
                attendance.save(update_fields=["check_out", "updated_at"])

            seconds = attendance.worked_seconds
            hours, remainder = divmod(seconds, 3600)
            minutes = remainder // 60

            return Response(
                {
                    "message": "Check-out successful.",
                    "username": request.user.username,
                    "check_out": attendance.check_out,
                    "worked_hours": hours,
                    "worked_minutes": minutes,
                },
                status=status.HTTP_200_OK,
            )

        return Response(
            {"detail": "Use action: check_in or check_out."},
            status=status.HTTP_400_BAD_REQUEST,
        )


# ---------------------------------------------------------------- admin side
from rest_framework import generics  # noqa: E402
from apps.accounts.permissions import capability  # noqa: E402

from .serializers import AttendanceAdminSerializer  # noqa: E402


class AttendanceManageListCreateAPIView(generics.ListCreateAPIView):
    """
    Admin: list/add attendance records.
    GET /api/attendance/manage/?date=YYYY-MM-DD  (or date_from/date_to, user)
    """

    serializer_class = AttendanceAdminSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [capability("manage_attendance")]

    def get_queryset(self):
        qs = Attendance.objects.select_related("user")
        p = self.request.query_params
        if p.get("date"):
            qs = qs.filter(date=p["date"])
        if p.get("date_from"):
            qs = qs.filter(date__gte=p["date_from"])
        if p.get("date_to"):
            qs = qs.filter(date__lte=p["date_to"])
        if p.get("user"):
            qs = qs.filter(user=p["user"])
        return qs.order_by("-date", "user__username")


class AttendanceManageDetailAPIView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = AttendanceAdminSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [capability("manage_attendance")]
    queryset = Attendance.objects.select_related("user")


# ------------------------------------------------------------ employee history
from datetime import timedelta  # noqa: E402

from django.utils.dateparse import parse_date  # noqa: E402
from rest_framework.exceptions import ValidationError  # noqa: E402


class MyAttendanceHistoryAPIView(generics.ListAPIView):
    """
    GET /api/attendance/history/?date_from=YYYY-MM-DD&date_to=YYYY-MM-DD

    The logged-in user's OWN attendance records, newest first.
    Defaults to the last 30 days; never more than 366 rows.
    """

    serializer_class = AttendanceAdminSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]
    pagination_class = None

    def _date(self, name, default):
        raw = self.request.query_params.get(name)
        if not raw:
            return default
        try:
            value = parse_date(raw)
        except ValueError:
            value = None
        if value is None:
            raise ValidationError({name: "Use YYYY-MM-DD."})
        return value

    def get_queryset(self):
        date_to = self._date("date_to", timezone.localdate())
        date_from = self._date("date_from", date_to - timedelta(days=29))
        if date_from > date_to:
            raise ValidationError({"date_from": "date_from cannot be after date_to."})
        return Attendance.objects.filter(
            user=self.request.user, date__range=(date_from, date_to)
        ).order_by("-date")[:366]

