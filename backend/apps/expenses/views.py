from datetime import date

from django.db.models import Count, Q, Sum
from django.db.models.functions import TruncMonth
from django.utils import timezone
from rest_framework import generics
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import capability

from .models import Expense
from .serializers import ExpenseSerializer

PERMS = [IsAuthenticated, capability("manage_expenses")]


def filtered(request, qs=None):
    """Optional filters: ?category= ?project= ?from=YYYY-MM-DD ?to=YYYY-MM-DD ?q="""
    qs = Expense.objects.select_related("project", "created_by") if qs is None else qs
    p = request.query_params
    if p.get("category"):
        qs = qs.filter(category=p["category"])
    if p.get("project"):
        qs = qs.filter(project_id=p["project"])
    if p.get("from"):
        qs = qs.filter(date__gte=p["from"])
    if p.get("to"):
        qs = qs.filter(date__lte=p["to"])
    if p.get("q"):
        qs = qs.filter(Q(title__icontains=p["q"]) | Q(notes__icontains=p["q"]))
    return qs


class ExpenseListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = ExpenseSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = PERMS

    def get_queryset(self):
        return filtered(self.request)

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)


class ExpenseDetailAPIView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = ExpenseSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = PERMS
    queryset = Expense.objects.select_related("project", "created_by")


def _total(qs):
    return float(qs.aggregate(t=Sum("amount"))["t"] or 0)


def _breakdown(qs):
    rows = (
        qs.values("category")
        .annotate(total=Sum("amount"), count=Count("id"))
        .order_by("-total")
    )
    return [
        {"category": r["category"], "total": float(r["total"]), "count": r["count"]}
        for r in rows
    ]


def _shift_month(d, delta):
    """First day of the month `delta` months away from d."""
    index = d.year * 12 + (d.month - 1) + delta
    return date(index // 12, index % 12 + 1, 1)


class ExpenseSummaryAPIView(APIView):
    """Numbers for the Expenses screen header and charts."""

    authentication_classes = [TokenAuthentication]
    permission_classes = PERMS

    def get(self, request):
        qs = Expense.objects.all()
        today = timezone.localdate()
        this_month = today.replace(day=1)
        last_month = _shift_month(this_month, -1)
        first_of_window = _shift_month(this_month, -5)

        month_qs = qs.filter(date__gte=this_month)
        prev_qs = qs.filter(date__gte=last_month, date__lt=this_month)

        by_month = {
            r["m"]: float(r["total"])
            for r in qs.filter(date__gte=first_of_window)
            .annotate(m=TruncMonth("date"))
            .values("m")
            .annotate(total=Sum("amount"))
        }
        monthly = []
        for i in range(-5, 1):
            first = _shift_month(this_month, i)
            monthly.append(
                {"month": first.strftime("%Y-%m"), "total": by_month.get(first, 0.0)}
            )

        return Response(
            {
                "total": _total(qs),
                "count": qs.count(),
                "this_month_total": _total(month_qs),
                "this_month_count": month_qs.count(),
                "last_month_total": _total(prev_qs),
                "by_category": _breakdown(qs),
                "by_category_month": _breakdown(month_qs),
                "monthly": monthly,
            }
        )
