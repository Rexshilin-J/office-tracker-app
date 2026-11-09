
from rest_framework import serializers
from .models import Client


class ClientSerializer(serializers.ModelSerializer):
    created_by_username = serializers.CharField(
        source="created_by.username",
        read_only=True,
        default=None,
    )

    class Meta:
        model = Client
        fields = [
            "id",
            "company_name",
            "contact_person",
            "email",
            "phone",
            "address",
            "website",
            "notes",
            "is_active",
            "created_by",
            "created_by_username",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "created_by",
            "created_by_username",
            "created_at",
            "updated_at",
        ]
