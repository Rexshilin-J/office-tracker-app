from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.authentication import TokenAuthentication
from rest_framework.authtoken.models import Token
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .permissions import (
    EMPLOYEE,
    MANAGER,
    SUPER_ADMIN,
    can,
    capabilities_for,
    capability,
    get_role,
)
from .serializers import EmployeeRegistrationSerializer, EmployeeUpdateSerializer


def serialize_user(user, with_capabilities=False):
    profile = getattr(user, "employee_profile", None)
    data = {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "is_active": user.is_active,
        "role": get_role(user),
        "employee_id": profile.employee_id if profile else "",
        "department": profile.department if profile else "",
        "designation": profile.designation if profile else "",
        "work_mode": profile.work_mode if profile else "",
        "phone": profile.phone if profile else "",
    }
    if with_capabilities:
        data["capabilities"] = capabilities_for(user)
    return data


class EmployeeRegistrationAPIView(APIView):
    """Only a Super Admin can create accounts (any role)."""

    authentication_classes = [TokenAuthentication]
    permission_classes = [capability("manage_accounts")]

    @transaction.atomic
    def post(self, request):
        serializer = EmployeeRegistrationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        return Response(
            {
                "message": "Account created successfully.",
                "user_id": user.id,
                "username": user.username,
                "employee_id": user.employee_profile.employee_id,
                "role": user.employee_profile.role,
            },
            status=status.HTTP_201_CREATED,
        )


def find_login_user(identifier):
    """
    Who is trying to log in? Accepts the username, the Employee ID or the email
    (the last two and a differently-cased username are case-insensitive).

    An exact username always wins. Anything ambiguous (two accounts match) is
    refused rather than guessed, so nobody can log in as the wrong person.
    """
    ident = (identifier or "").strip()
    if not ident:
        return None
    for matches in (
        User.objects.filter(username=ident),
        User.objects.filter(employee_profile__employee_id__iexact=ident),
        User.objects.filter(username__iexact=ident),
        User.objects.filter(email__iexact=ident),
    ):
        found = list(matches[:2])
        if len(found) == 1:
            return found[0]
    return None


class LoginAPIView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        username = request.data.get("username", "")
        password = request.data.get("password", "")

        candidate = find_login_user(username)
        # Always call authenticate (even with no match) so the response time
        # does not reveal whether an account exists.
        user = authenticate(
            username=candidate.username if candidate else username,
            password=password,
        )

        if user is None or not user.is_active:
            return Response(
                {"detail": "Invalid username or password."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        token, _ = Token.objects.get_or_create(user=user)
        return Response(
            {
                "message": "Login successful.",
                "token": token.key,
                "user": serialize_user(user, with_capabilities=True),
            },
            status=status.HTTP_200_OK,
        )


class MeAPIView(APIView):
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(serialize_user(request.user, with_capabilities=True))


class LogoutAPIView(APIView):
    """POST /api/auth/logout/ - revoke the caller's token so it stops working."""

    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def post(self, request):
        Token.objects.filter(user=request.user).delete()
        return Response({"message": "Logged out."}, status=status.HTTP_200_OK)


class EmployeeListAPIView(APIView):
    """GET /api/auth/employees/ - staff directory (Super Admin, HR, Manager)."""

    authentication_classes = [TokenAuthentication]
    permission_classes = [capability("view_employees")]

    def get(self, request):
        users = User.objects.select_related("employee_profile").order_by("username")
        people = [serialize_user(u) for u in users]

        # Managers only need people they can assign work to.
        if get_role(request.user) == MANAGER:
            people = [p for p in people if p["role"] in (EMPLOYEE, MANAGER)]
        return Response(people)


class EmployeeDetailAPIView(APIView):
    """
    PATCH  /api/auth/employees/<id>/
        Super Admin: any account (details, role, active flag, password)
        HR: EMPLOYEE accounts only, and cannot change roles
    DELETE /api/auth/employees/<id>/   Super Admin only
    """

    authentication_classes = [TokenAuthentication]
    permission_classes = [capability("view_employees")]

    def get_user(self, pk):
        return get_object_or_404(
            User.objects.select_related("employee_profile"), pk=pk
        )

    def deny(self, message):
        return Response({"detail": message}, status=status.HTTP_403_FORBIDDEN)

    @transaction.atomic
    def patch(self, request, pk):
        if not can(request.user, "manage_employees"):
            return self.deny("You cannot edit employees.")

        user = self.get_user(pk)
        actor_role = get_role(request.user)

        if actor_role != SUPER_ADMIN:
            if get_role(user) != EMPLOYEE:
                return self.deny("You can only manage employee accounts.")
            if "role" in request.data:
                return self.deny("Only a Super Admin can change roles.")

        if user.pk == request.user.pk:
            if request.data.get("is_active") in (False, "false", "False", 0):
                return Response(
                    {"detail": "You cannot deactivate your own account."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            new_role = request.data.get("role")
            if new_role and new_role != SUPER_ADMIN:
                return Response(
                    {"detail": "You cannot remove your own Super Admin role."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        serializer = EmployeeUpdateSerializer(
            data=request.data, partial=True, context={"user": user}
        )
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        # A deactivated user must be logged out everywhere.
        if not user.is_active:
            Token.objects.filter(user=user).delete()

        return Response(serialize_user(self.get_user(pk)))

    @transaction.atomic
    def delete(self, request, pk):
        if not can(request.user, "manage_accounts"):
            return self.deny("Only a Super Admin can delete accounts.")

        user = self.get_user(pk)
        if user.pk == request.user.pk:
            return Response(
                {"detail": "You cannot delete your own account."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
