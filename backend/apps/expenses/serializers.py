from decimal import Decimal

from rest_framework import serializers

from .models import Expense, ExpenseClaim


class ExpenseSerializer(serializers.ModelSerializer):
    category_label = serializers.CharField(source="get_category_display", read_only=True)
    payment_method_label = serializers.CharField(
        source="get_payment_method_display", read_only=True
    )
    project_name = serializers.CharField(source="project.name", read_only=True, default=None)
    created_by_name = serializers.CharField(
        source="created_by.username", read_only=True, default=None
    )

    class Meta:
        model = Expense
        fields = [
            "id",
            "title",
            "amount",
            "category",
            "category_label",
            "payment_method",
            "payment_method_label",
            "date",
            "notes",
            "project",
            "project_name",
            "created_by",
            "created_by_name",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_by", "created_at", "updated_at"]

    def validate_title(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Title is required.")
        return value

    def validate_amount(self, value):
        if value <= Decimal("0"):
            raise serializers.ValidationError("Amount must be greater than 0.")
        return value


class ExpenseClaimSerializer(serializers.ModelSerializer):
    """What an employee sends (title, amount, ...) and sees (plus status)."""

    category_label = serializers.CharField(source="get_category_display", read_only=True)
    payment_method_label = serializers.CharField(
        source="get_payment_method_display", read_only=True
    )
    status_label = serializers.CharField(source="get_status_display", read_only=True)
    project_name = serializers.CharField(source="project.name", read_only=True, default=None)
    reviewed_by_name = serializers.CharField(
        source="reviewed_by.username", read_only=True, default=None
    )

    class Meta:
        model = ExpenseClaim
        fields = [
            "id",
            "title",
            "amount",
            "category",
            "category_label",
            "payment_method",
            "payment_method_label",
            "date",
            "notes",
            "project",
            "project_name",
            "status",
            "status_label",
            "review_note",
            "reviewed_by_name",
            "reviewed_at",
            "created_at",
        ]
        # status and everything about the review are decided by the approver.
        read_only_fields = [
            "id",
            "status",
            "review_note",
            "reviewed_at",
            "created_at",
        ]

    def validate_title(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Title is required.")
        return value

    def validate_amount(self, value):
        if value <= Decimal("0"):
            raise serializers.ValidationError("Amount must be greater than 0.")
        return value

    def validate_date(self, value):
        from django.utils import timezone

        if value > timezone.localdate():
            raise serializers.ValidationError("Date cannot be in the future.")
        return value

    def validate_project(self, value):
        # Only projects the employee can actually see.
        if value is None:
            return value
        from apps.accounts.permissions import visible_projects

        user = self.context["request"].user
        if not visible_projects(user).filter(pk=value.pk).exists():
            raise serializers.ValidationError("You are not a member of this project.")
        return value
