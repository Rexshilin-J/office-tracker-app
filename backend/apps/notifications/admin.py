from django.contrib import admin

from .models import Announcement, Notification


@admin.register(Announcement)
class AnnouncementAdmin(admin.ModelAdmin):
    """Add an announcement here: every active user gets it as a notification."""

    list_display = ("title", "created_by", "created_at")
    search_fields = ("title", "message")
    readonly_fields = ("created_by", "created_at")

    def save_model(self, request, obj, form, change):
        if not change:
            obj.created_by = request.user
        super().save_model(request, obj, form, change)


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("recipient", "kind", "title", "is_read", "created_at")
    list_filter = ("kind", "is_read")
    search_fields = ("title", "message", "recipient__username")
