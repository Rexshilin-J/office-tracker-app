from django.conf import settings
from django.db import models
from django.utils import timezone


class Expense(models.Model):
    CATEGORY_CHOICES = [
        ("SALARY", "Salary"),
        ("RENT", "Rent"),
        ("UTILITIES", "Utilities"),
        ("TRAVEL", "Travel"),
        ("FOOD", "Food"),
        ("SUPPLIES", "Office Supplies"),
        ("SOFTWARE", "Software"),
        ("MARKETING", "Marketing"),
        ("MAINTENANCE", "Maintenance"),
        ("OTHER", "Other"),
    ]

    PAYMENT_CHOICES = [
        ("CASH", "Cash"),
        ("UPI", "UPI"),
        ("CARD", "Card"),
        ("BANK", "Bank Transfer"),
        ("CHEQUE", "Cheque"),
    ]

    title = models.CharField(max_length=200)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    category = models.CharField(max_length=20, choices=CATEGORY_CHOICES, default="OTHER")
    payment_method = models.CharField(max_length=20, choices=PAYMENT_CHOICES, default="CASH")
    date = models.DateField(default=timezone.localdate)
    notes = models.TextField(blank=True)

    project = models.ForeignKey(
        "projects.Project",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="expenses",
    )

    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="created_expenses",
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-date", "-id"]

    def __str__(self):
        return f"{self.title} - {self.amount}"
