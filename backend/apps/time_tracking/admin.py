from django.contrib import admin
from .models import TimeEntry


@admin.register(TimeEntry)
class TimeEntryAdmin(admin.ModelAdmin):
    list_display = ("user", "task", "date", "status", "duration_seconds")
    list_filter = ("status", "date")
