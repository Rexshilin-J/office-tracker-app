from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework import serializers

from .models import Project


class ProjectSerializer(serializers.ModelSerializer):
    client_name = serializers.CharField(
        source="client.company_name",
        read_only=True,
        default=None,
    )
    project_manager_name = serializers.CharField(
        source="project_manager.username",
        read_only=True,
        default=None,
    )
    team_members = serializers.PrimaryKeyRelatedField(
        many=True,
        queryset=User.objects.filter(is_active=True),
        required=False,
    )

    # Read-only summary used by the project detail screen.
    team_members_detail = serializers.SerializerMethodField()
    total_tasks = serializers.SerializerMethodField()
    completed_tasks = serializers.SerializerMethodField()
    progress_percent = serializers.SerializerMethodField()
    tracked_seconds = serializers.SerializerMethodField()
    is_overdue = serializers.SerializerMethodField()

    class Meta:
        model = Project
        fields = [
            "id",
            "name",
            "description",
            "client",
            "client_name",
            "project_manager",
            "project_manager_name",
            "team_members",
            "team_members_detail",
            "start_date",
            "deadline",
            "status",
            "priority",
            "total_tasks",
            "completed_tasks",
            "progress_percent",
            "tracked_seconds",
            "is_overdue",
            "created_by",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "created_by",
            "created_at",
            "updated_at",
            "client_name",
            "project_manager_name",
        ]

    # ---- computed fields (use annotations from the view when present) ----
    def get_team_members_detail(self, obj):
        return [{"id": u.id, "username": u.username} for u in obj.team_members.all()]

    def get_total_tasks(self, obj):
        value = getattr(obj, "total_tasks_n", None)
        return value if value is not None else obj.tasks.count()

    def get_completed_tasks(self, obj):
        value = getattr(obj, "completed_tasks_n", None)
        if value is not None:
            return value
        return obj.tasks.filter(status="COMPLETED").count()

    def get_progress_percent(self, obj):
        total = self.get_total_tasks(obj)
        if not total:
            return 0
        return round(self.get_completed_tasks(obj) * 100 / total)

    def get_tracked_seconds(self, obj):
        value = getattr(obj, "tracked_n", None)
        if value is not None:
            return value
        from django.db.models import Sum

        from apps.time_tracking.models import TimeEntry

        return (
            TimeEntry.objects.filter(task__project=obj, status="STOPPED").aggregate(
                t=Sum("duration_seconds")
            )["t"]
            or 0
        )

    def get_is_overdue(self, obj):
        return bool(
            obj.deadline
            and obj.deadline < timezone.localdate()
            and obj.status not in ("COMPLETED", "CANCELLED")
        )

    # ---- validation ----
    def validate_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Project name is required.")
        return value

    def validate(self, attrs):
        instance = self.instance
        start = attrs.get("start_date", instance.start_date if instance else None)
        deadline = attrs.get("deadline", instance.deadline if instance else None)
        if start and deadline and deadline < start:
            raise serializers.ValidationError(
                {"deadline": "Deadline cannot be before the start date."}
            )

        # Do not remove someone from the team while they still have open tasks.
        if instance is not None and "team_members" in attrs:
            from apps.tasks.models import Task

            manager = attrs.get("project_manager", instance.project_manager)
            keep = {u.pk for u in attrs["team_members"]}
            if manager:
                keep.add(manager.pk)
            removed = set(instance.team_members.values_list("pk", flat=True)) - keep
            if removed:
                busy = (
                    Task.objects.filter(project=instance, assigned_to__in=removed)
                    .exclude(status="COMPLETED")
                    .select_related("assigned_to")
                )
                names = sorted({t.assigned_to.username for t in busy})
                if names:
                    raise serializers.ValidationError(
                        {
                            "team_members": (
                                "Reassign open tasks first: " + ", ".join(names) + "."
                            )
                        }
                    )
        return attrs
