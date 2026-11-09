from django.urls import path

from .views import (
    AttendanceReportAPIView,
    DashboardAPIView,
    ProjectReportAPIView,
    TaskReportAPIView,
    WorkTimeReportAPIView,
)

urlpatterns = [
    path("dashboard/", DashboardAPIView.as_view(), name="report-dashboard"),
    path("attendance/", AttendanceReportAPIView.as_view(), name="report-attendance"),
    path("projects/", ProjectReportAPIView.as_view(), name="report-projects"),
    path("tasks/", TaskReportAPIView.as_view(), name="report-tasks"),
    path("work-time/", WorkTimeReportAPIView.as_view(), name="report-work-time"),
]
