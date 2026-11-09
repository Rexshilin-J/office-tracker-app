
from django.contrib import admin
from .models import EmployeeProfile


@admin.register(EmployeeProfile)
class EmployeeProfileAdmin(admin.ModelAdmin):
    list_display = (
        "employee_id",
        "user",
        "role",
        "department",
        "work_mode",
        "is_active",
    )
    list_filter = ("role", "work_mode", "is_active")
    search_fields = ("employee_id", "user__username", "user__email")
