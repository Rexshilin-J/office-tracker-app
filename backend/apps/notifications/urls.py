from django.urls import path

from .views import (
    MarkAllReadAPIView,
    MarkReadAPIView,
    NotificationListAPIView,
    UnreadCountAPIView,
)

urlpatterns = [
    path("", NotificationListAPIView.as_view(), name="notification-list"),
    path("unread-count/", UnreadCountAPIView.as_view(), name="notification-unread-count"),
    path("read-all/", MarkAllReadAPIView.as_view(), name="notification-read-all"),
    path("<int:pk>/read/", MarkReadAPIView.as_view(), name="notification-read"),
]
