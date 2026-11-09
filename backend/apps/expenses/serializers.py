from decimal import Decimal

from rest_framework import serializers

from .models import Expense


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
