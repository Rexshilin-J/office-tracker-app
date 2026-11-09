
from django.contrib import admin
from .models import Client


@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = (
        "company_name",
        "contact_person",
        "email",
        "phone",
        "is_active",
    )
    list_filter = ("is_active",)
    search_fields = ("company_name", "contact_person", "email")
    readonly_fields = ("created_at", "updated_at")
