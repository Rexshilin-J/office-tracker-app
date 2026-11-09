
from django.contrib.auth.models import User
from rest_framework import serializers

from .models import EmployeeProfile


class EmployeeRegistrationSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)
    email = serializers.EmailField()
    password = serializers.CharField(
        write_only=True,
        min_length=8,
        trim_whitespace=False,
    )
    employee_id = serializers.CharField(max_length=20)
    phone = serializers.CharField(
        max_length=15,
        required=False,
        allow_blank=True,
    )
    role = serializers.ChoiceField(
        choices=EmployeeProfile.ROLE_CHOICES,
        default="EMPLOYEE",
    )
    department = serializers.CharField(
        max_length=100,
        required=False,
        allow_blank=True,
    )
    designation = serializers.CharField(
        max_length=100,
        required=False,
        allow_blank=True,
    )
    work_mode = serializers.ChoiceField(
        choices=EmployeeProfile.WORK_MODE_CHOICES,
        default="HYBRID",
    )

    def validate_username(self, value):
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("Username already exists.")
        return value

    def validate_email(self, value):
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("Email already exists.")
        return value

    def validate_employee_id(self, value):
        if EmployeeProfile.objects.filter(employee_id=value).exists():
            raise serializers.ValidationError("Employee ID already exists.")
        return value

    def create(self, validated_data):
        password = validated_data.pop("password")

        profile_fields = {
            key: validated_data.pop(key)
            for key in [
                "employee_id",
                "phone",
                "role",
                "department",
                "designation",
                "work_mode",
            ]
            if key in validated_data
        }

        user = User.objects.create_user(
            password=password,
            **validated_data,
        )

        if profile_fields.get("role") == "SUPER_ADMIN":
            user.is_staff = True
            user.save(update_fields=["is_staff"])

        EmployeeProfile.objects.create(
            user=user,
            **profile_fields,
        )

        return user


class EmployeeUpdateSerializer(serializers.Serializer):
    """Admin edit of a user + profile. Every field is optional."""

    email = serializers.EmailField(required=False)
    is_active = serializers.BooleanField(required=False)
    password = serializers.CharField(
        write_only=True, min_length=8, required=False, trim_whitespace=False
    )
    employee_id = serializers.CharField(max_length=20, required=False)
    phone = serializers.CharField(max_length=15, required=False, allow_blank=True)
    role = serializers.ChoiceField(choices=EmployeeProfile.ROLE_CHOICES, required=False)
    department = serializers.CharField(max_length=100, required=False, allow_blank=True)
    designation = serializers.CharField(max_length=100, required=False, allow_blank=True)
    work_mode = serializers.ChoiceField(
        choices=EmployeeProfile.WORK_MODE_CHOICES, required=False
    )

    PROFILE_FIELDS = ["employee_id", "phone", "role", "department", "designation", "work_mode"]

    def validate_email(self, value):
        if User.objects.filter(email=value).exclude(pk=self.context["user"].pk).exists():
            raise serializers.ValidationError("Email already exists.")
        return value

    def validate_employee_id(self, value):
        qs = EmployeeProfile.objects.filter(employee_id=value)
        qs = qs.exclude(user=self.context["user"])
        if qs.exists():
            raise serializers.ValidationError("Employee ID already exists.")
        return value

    def validate(self, attrs):
        user = self.context["user"]
        has_profile = hasattr(user, "employee_profile")
        touches_profile = any(k in attrs for k in self.PROFILE_FIELDS)
        if touches_profile and not has_profile and "employee_id" not in attrs:
            raise serializers.ValidationError(
                {"employee_id": "Employee ID is required for this user."}
            )
        return attrs

    def save(self, **kwargs):
        user = self.context["user"]
        data = self.validated_data

        if "email" in data:
            user.email = data["email"]
        if "is_active" in data:
            user.is_active = data["is_active"]
        if "password" in data:
            user.set_password(data["password"])
        if data.get("role") == "SUPER_ADMIN":
            user.is_staff = True
        elif "role" in data:
            user.is_staff = False
        user.save()

        profile_data = {k: data[k] for k in self.PROFILE_FIELDS if k in data}
        if profile_data:
            profile, _ = EmployeeProfile.objects.get_or_create(
                user=user,
                defaults={"employee_id": profile_data.get("employee_id", "")},
            )
            for key, value in profile_data.items():
                setattr(profile, key, value)
            profile.save()
        return user
