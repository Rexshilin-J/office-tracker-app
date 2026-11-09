from django.urls import path

from .views import (
    ExpenseDetailAPIView,
    ExpenseListCreateAPIView,
    ExpenseSummaryAPIView,
)

urlpatterns = [
    path("", ExpenseListCreateAPIView.as_view(), name="expense-list-create"),
    path("summary/", ExpenseSummaryAPIView.as_view(), name="expense-summary"),
    path("<int:pk>/", ExpenseDetailAPIView.as_view(), name="expense-detail"),
]
