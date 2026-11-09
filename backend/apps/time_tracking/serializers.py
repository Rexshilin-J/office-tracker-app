from django.utils import timezone
from rest_framework import serializers

from .models import TimeEntry


class TimeEntrySerializer(serializers.ModelSerializer):
    username = serializers.CharField(source="user.username", read_only=True)
    task_title = serializers.CharField(source="task.title", read_only=True)
    project_id = serializers.IntegerField(source="task.project_id", read_only=True)
    elapsed_seconds = serializers.SerializerMethodField()

    class Meta:
        model = TimeEntry
        fields = [
            "id",
            "user",
            "username",
            "task",
            "task_title",
            "project_id",
            "date",
            "started_at",
            "ended_at",
            "paused_at",
            "paused_seconds",
            "duration_seconds",
            "elapsed_seconds",
            "status",
        ]
        read_only_fields = fields

    def get_elapsed_seconds(self, obj):
        return obj.elapsed_seconds(timezone.now())
