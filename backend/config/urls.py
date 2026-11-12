
from django.contrib import admin
from django.urls import include, path
from django.http import JsonResponse


def api_home(request):
    return JsonResponse({
        "message": "OfficeTracker API is running",
        "endpoints": {
            "admin": "/admin/",
            "login": "/api/auth/login/",
            "register": "/api/auth/register/",
            "attendance": "/api/attendance/",
            "clients": "/api/clients/",
            "projects": "/api/projects/",
            "tasks": "/api/tasks/",
            "time_tracking": "/api/time-tracking/",
            "reports": "/api/reports/",
        }
    })


urlpatterns = [
    path("", api_home, name="api-home"),
    path("admin/", admin.site.urls),
    path("api/auth/", include("apps.accounts.urls")),
    path("api/attendance/", include("apps.attendance.urls")),
    path("api/clients/", include("apps.clients.urls")),
    path("api/projects/", include("apps.projects.urls")),
    path("api/tasks/", include("apps.tasks.urls")),
    path("api/time-tracking/", include("apps.time_tracking.urls")),
    path("api/reports/", include("apps.reports.urls")),
    path("api/expenses/", include("apps.expenses.urls")),
    path("api/notifications/", include("apps.notifications.urls")),
]
