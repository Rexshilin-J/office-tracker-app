
from django.db import models
from django.contrib.auth.models import User


class EmployeeProfile(models.Model):
    ROLE_CHOICES = [
        ("SUPER_ADMIN", "Super Admin"),
        ("HR", "HR"),
        ("MANAGER", "Manager"),
        ("EMPLOYEE", "Employee"),
    ]

    WORK_MODE_CHOICES = [
        ("OFFICE", "Office"),
        ("REMOTE", "Remote"),
        ("HYBRID", "Hybrid"),
    ]

    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name="employee_profile",
    )
    employee_id = models.CharField(max_length=20, unique=True)
    phone = models.CharField(max_length=15, blank=True)
    role = models.CharField(
        max_length=20,
        choices=ROLE_CHOICES,
        default="EMPLOYEE",
    )
    department = models.CharField(max_length=100, blank=True)
    designation = models.CharField(max_length=100, blank=True)
    work_mode = models.CharField(
        max_length=20,
        choices=WORK_MODE_CHOICES,
        default="HYBRID",
    )
    is_active = models.BooleanField(default=True)
    joined_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.employee_id} - {self.user.username}"
