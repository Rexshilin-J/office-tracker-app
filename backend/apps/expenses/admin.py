from django.contrib import admin

from django.utils import timezone

from .models import Expense, ExpenseClaim


@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ("title", "amount", "category", "payment_method", "date", "project")
    list_filter = ("category", "payment_method", "date")
    search_fields = ("title", "notes")


@admin.register(ExpenseClaim)
class ExpenseClaimAdmin(admin.ModelAdmin):
    """
    Where claims get approved or rejected.
    To reject: open the claim, set Status = Rejected and write the reason.
    """

    list_display = ("title", "amount", "submitted_by", "category", "date", "status")
    list_filter = ("status", "category", "date")
    search_fields = ("title", "notes", "submitted_by__username")
    readonly_fields = ("submitted_by", "reviewed_by", "reviewed_at", "created_at")
    actions = ["approve_selected"]

    @admin.action(description="Approve selected pending claims")
    def approve_selected(self, request, queryset):
        done = 0
        for claim in queryset.filter(status="PENDING"):
            claim.review(request.user, "APPROVED")
            done += 1
        self.message_user(request, f"{done} claim(s) approved.")

    def save_model(self, request, obj, form, change):
        if change and "status" in form.changed_data and obj.status != "PENDING":
            obj.reviewed_by = request.user
            obj.reviewed_at = timezone.now()
        super().save_model(request, obj, form, change)
