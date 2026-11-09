from django.conf import settings
from django.db import models
from django.db.models import Q


class TimeEntry(models.Model):
    STATUS_CHOICES = [
        ("RUNNING", "Running"),
        ("PAUSED", "Paused"),
        ("STOPPED", "Stopped"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="time_entries",
    )
    task = models.ForeignKey(
        "tasks.Task",
        on_delete=models.CASCADE,
        related_name="time_entries",
    )
    date = models.DateField()
    started_at = models.DateTimeField()
    ended_at = models.DateTimeField(null=True, blank=True)
    paused_at = models.DateTimeField(null=True, blank=True)
    paused_seconds = models.PositiveIntegerField(default=0)
    duration_seconds = models.PositiveIntegerField(default=0)
    status = models.CharField(
        max_length=10,
        choices=STATUS_CHOICES,
        default="RUNNING",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-started_at"]
        constraints = [
            # A user can never have two active (running/paused) timers.
            models.UniqueConstraint(
                fields=["user"],
                condition=Q(status__in=["RUNNING", "PAUSED"]),
                name="one_active_timer_per_user",
            )
        ]

    def __str__(self):
        return f"{self.user} - {self.task_id} - {self.status}"

    def elapsed_seconds(self, now):
        """Worked seconds so far, excluding paused time."""
        if self.status == "STOPPED":
            return self.duration_seconds
        end = self.paused_at if self.status == "PAUSED" and self.paused_at else now
        total = int((end - self.started_at).total_seconds()) - self.paused_seconds
        return max(0, total)
