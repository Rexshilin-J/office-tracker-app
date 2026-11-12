from django.urls import path

from .views import (
    ExpenseDetailAPIView,
    ExpenseListCreateAPIView,
    MyClaimDetailAPIView,
    MyClaimListCreateAPIView,
    ExpenseSummaryAPIView,
)

urlpatterns = [
    path("", ExpenseListCreateAPIView.as_view(), name="expense-list-create"),
    path("claims/", MyClaimListCreateAPIView.as_view(), name="expense-claims"),
    path("claims/<int:pk>/", MyClaimDetailAPIView.as_view(), name="expense-claim-detail"),
    path("summary/", ExpenseSummaryAPIView.as_view(), name="expense-summary"),
    path("<int:pk>/", ExpenseDetailAPIView.as_view(), name="expense-detail"),
]
