from django.utils import timezone
from rest_framework import serializers

from .models import Task


class TaskSerializer(serializers.ModelSerializer):
    project_name = serializers.CharField(source="project.name", read_only=True)
    assigned_to_username = serializers.CharField(
        source="assigned_to.username",
        read_only=True,
        default=None,
    )

    class Meta:
        model = Task
        fields = [
            "id",
            "project",
            "project_name",
            "title",
            "description",
            "assigned_to",
            "assigned_to_username",
            "status",
            "priority",
            "due_date",
            "completed_at",
            "created_by",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "project_name",
            "assigned_to_username",
            "completed_at",
            "created_by",
            "created_at",
            "updated_at",
        ]

    def validate_due_date(self, value):
        # Only block past due dates when creating, so old tasks stay editable.
        if self.instance is None and value and value < timezone.localdate():
            raise serializers.ValidationError("Due date cannot be in the past.")
        return value

    def validate(self, attrs):
        instance = self.instance
        project = attrs.get("project", instance.project if instance else None)
        assignee = attrs.get(
            "assigned_to",
            instance.assigned_to if instance else None,
        )

        if instance and "project" in attrs and attrs["project"] != instance.project:
            raise serializers.ValidationError(
                {"project": "A task cannot be moved to another project."}
            )

        # Assignee must belong to the project's team (or be its manager).
        if assignee and project:
            is_member = project.team_members.filter(pk=assignee.pk).exists()
            is_manager = project.project_manager_id == assignee.pk
            if not (is_member or is_manager):
                raise serializers.ValidationError(
                    {"assigned_to": "Employee is not a member of this project."}
                )

        # Status transition rules.
        if instance and "status" in attrs and attrs["status"] != instance.status:
            allowed = Task.ALLOWED_TRANSITIONS.get(instance.status, set())
            if attrs["status"] not in allowed:
                raise serializers.ValidationError(
                    {
                        "status": (
                            f"Cannot change status from {instance.status} "
                            f"to {attrs['status']}."
                        )
                    }
                )

        return attrs

    def update(self, instance, validated_data):
        new_status = validated_data.get("status")
        if new_status and new_status != instance.status:
            if new_status == "COMPLETED":
                validated_data["completed_at"] = timezone.now()
            elif instance.status == "COMPLETED":
                validated_data["completed_at"] = None
        return super().update(instance, validated_data)
