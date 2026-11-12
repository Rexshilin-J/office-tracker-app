
from django.urls import path
from .views import (
    EmployeeDetailAPIView,
    EmployeeListAPIView,
    EmployeeRegistrationAPIView,
    LoginAPIView,
    LogoutAPIView,
    MeAPIView,
)

urlpatterns = [
    path("login/", LoginAPIView.as_view(), name="login"),
    path("logout/", LogoutAPIView.as_view(), name="logout"),
    path("me/", MeAPIView.as_view(), name="me"),
    path("employees/", EmployeeListAPIView.as_view(), name="employee-list"),
    path("employees/<int:pk>/", EmployeeDetailAPIView.as_view(), name="employee-detail"),
    path(
        "register/",
        EmployeeRegistrationAPIView.as_view(),
        name="employee-register",
    ),
]
