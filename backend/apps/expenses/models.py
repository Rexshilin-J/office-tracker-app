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


class ExpenseClaim(models.Model):
    """
    An expense an employee paid for and wants reimbursed.

    Kept separate from `Expense` (the company ledger) on purpose: a pending or
    rejected claim must never change the totals the Admin Expenses screen shows.
    """

    STATUS_CHOICES = [
        ("PENDING", "Pending"),
        ("APPROVED", "Approved"),
        ("REJECTED", "Rejected"),
    ]

    title = models.CharField(max_length=200)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    category = models.CharField(
        max_length=20, choices=Expense.CATEGORY_CHOICES, default="OTHER"
    )
    payment_method = models.CharField(
        max_length=20, choices=Expense.PAYMENT_CHOICES, default="CASH"
    )
    date = models.DateField(default=timezone.localdate)
    notes = models.TextField(blank=True)
    project = models.ForeignKey(
        "projects.Project",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="expense_claims",
    )

    submitted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="expense_claims",
    )
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default="PENDING")
    review_note = models.TextField(blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reviewed_expense_claims",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [models.Index(fields=["submitted_by", "status"])]

    def __str__(self):
        return f"{self.title} - {self.amount} ({self.status})"

    def clean(self):
        from django.core.exceptions import ValidationError

        if self.status == "REJECTED" and not self.review_note.strip():
            raise ValidationError({"review_note": "Give a reason when rejecting."})

    def review(self, reviewer, status, note=""):
        """Approve or reject a pending claim."""
        if status not in ("APPROVED", "REJECTED"):
            raise ValueError("status must be APPROVED or REJECTED")
        if self.status != "PENDING":
            raise ValueError("Only pending claims can be reviewed.")
        self.status = status
        self.review_note = note or ""
        self.clean()
        self.reviewed_by = reviewer
        self.reviewed_at = timezone.now()
        self.save()
