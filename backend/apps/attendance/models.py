
from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone


class Attendance(models.Model):
    STATUS_CHOICES = [
        ("PRESENT", "Present"),
        ("ABSENT", "Absent"),
        ("HALF_DAY", "Half Day"),
    ]

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="attendance_records",
    )
    date = models.DateField(default=timezone.localdate)
    check_in = models.DateTimeField(null=True, blank=True)
    check_out = models.DateTimeField(null=True, blank=True)
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default="PRESENT",
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "date"],
                name="unique_attendance_per_user_per_day",
            )
        ]
        ordering = ["-date", "-check_in"]

    def __str__(self):
        return f"{self.user.username} - {self.date}"

    @property
    def worked_seconds(self):
        if self.check_in and self.check_out:
            return max(
                0,
                int((self.check_out - self.check_in).total_seconds()),
            )
        return 0
