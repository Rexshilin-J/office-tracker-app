
from django.urls import path
from .views import (
    ClientListCreateAPIView,
    ClientDetailAPIView,
)

urlpatterns = [
    path("", ClientListCreateAPIView.as_view(), name="client-list-create"),
    path("<int:pk>/", ClientDetailAPIView.as_view(), name="client-detail"),
]
