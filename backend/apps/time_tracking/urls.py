from django.urls import path
from .views import ActiveTimerAPIView, TimeEntryDeleteAPIView, TimeTrackingAPIView

urlpatterns = [
    path("", TimeTrackingAPIView.as_view(), name="time-tracking"),
    path("active/", ActiveTimerAPIView.as_view(), name="time-tracking-active"),
    path("<int:pk>/", TimeEntryDeleteAPIView.as_view(), name="time-entry-delete"),
]
