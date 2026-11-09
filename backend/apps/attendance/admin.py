
from django.contrib import admin
from .models import Attendance


@admin.register(Attendance)
class AttendanceAdmin(admin.ModelAdmin):
    list_display = (
        "user",
        "date",
        "check_in",
        "check_out",
        "status",
    )

    list_filter = ("date", "status")
    search_fields = ("user__username",)
    readonly_fields = ("created_at", "updated_at")
