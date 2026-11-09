from rest_framework import serializers

from .models import Attendance


class AttendanceAdminSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source="user.username", read_only=True)
    worked_seconds = serializers.IntegerField(read_only=True)

    class Meta:
        model = Attendance
        fields = [
            "id",
            "user",
            "username",
            "date",
            "check_in",
            "check_out",
            "status",
            "worked_seconds",
        ]
        read_only_fields = ["id", "username", "worked_seconds"]

    def validate(self, attrs):
        instance = self.instance
        check_in = attrs.get("check_in", instance.check_in if instance else None)
        check_out = attrs.get("check_out", instance.check_out if instance else None)

        if check_out and not check_in:
            raise serializers.ValidationError(
                {"check_out": "Check-out needs a check-in time."}
            )
        if check_in and check_out and check_out <= check_in:
            raise serializers.ValidationError(
                {"check_out": "Check-out must be after check-in."}
            )
        return attrs
