
from django.contrib import admin
from .models import Project


@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = (
        "name",
        "client",
        "project_manager",
        "status",
        "priority",
        "deadline",
    )
    list_filter = ("status", "priority")
    search_fields = ("name", "description")
