
from django.urls import path
from .views import (
    AttendanceAPIView,
    AttendanceManageDetailAPIView,
    AttendanceManageListCreateAPIView,
)

urlpatterns = [
    path("", AttendanceAPIView.as_view(), name="attendance"),
    path("manage/", AttendanceManageListCreateAPIView.as_view(), name="attendance-manage"),
    path("manage/<int:pk>/", AttendanceManageDetailAPIView.as_view(), name="attendance-manage-detail"),
]
