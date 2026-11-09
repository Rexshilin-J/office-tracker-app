"""
Central place for roles and what each role is allowed to do.

Roles
  SUPER_ADMIN  creates every account, full access to everything
  HR           manages employees (edit / deactivate / password) and attendance
  MANAGER      manages projects and tasks of their own projects, sees their team
  EMPLOYEE     works on assigned tasks, checks in/out, tracks time

To change who can do what, edit CAPABILITIES below - nothing else.
"""
from django.db.models import Q
from rest_framework.permissions import BasePermission

SUPER_ADMIN = "SUPER_ADMIN"
HR = "HR"
MANAGER = "MANAGER"
EMPLOYEE = "EMPLOYEE"

CAPABILITIES = {
    # create users, change roles, permanently delete users, manage clients
    "manage_accounts": {SUPER_ADMIN},
    "manage_clients": {SUPER_ADMIN},
    # company expenses (create / edit / delete / reports)
    "manage_expenses": {SUPER_ADMIN},
    # see the employee directory (needed to assign work)
    "view_employees": {SUPER_ADMIN, HR, MANAGER},
    # edit / deactivate / reset password of EMPLOYEE accounts
    "manage_employees": {SUPER_ADMIN, HR},
    "manage_attendance": {SUPER_ADMIN, HR},
    # projects + tasks (managers: only the projects they manage)
    "manage_work": {SUPER_ADMIN, MANAGER},
    "delete_time_entries": {SUPER_ADMIN},
    "view_dashboard": {SUPER_ADMIN, HR, MANAGER},
    "view_attendance_report": {SUPER_ADMIN, HR},
    "view_work_reports": {SUPER_ADMIN, MANAGER},
}


def get_role(user):
    if not user or not user.is_authenticated:
        return None
    cached = getattr(user, "_role_cache", None)
    if cached:
        return cached

    profile = getattr(user, "employee_profile", None)
    role = profile.role if profile else None

    if user.is_superuser or role == "ADMIN":  # "ADMIN" = legacy value
        role = SUPER_ADMIN
    elif role is None:
        role = SUPER_ADMIN if user.is_staff else EMPLOYEE

    user._role_cache = role
    return role


def can(user, capability):
    return get_role(user) in CAPABILITIES.get(capability, set())


def capabilities_for(user):
    return {name: can(user, name) for name in CAPABILITIES}


def capability(name):
    """Build a DRF permission class: allowed only if the role has `name`."""

    class _HasCapability(BasePermission):
        def has_permission(self, request, view):
            return can(request.user, name)

    _HasCapability.__name__ = f"Can_{name}"
    return _HasCapability


# ----------------------------------------------------------- data scoping
def managed_projects(user):
    """Projects the user may edit."""
    from apps.projects.models import Project

    role = get_role(user)
    if role == SUPER_ADMIN:
        return Project.objects.all()
    if role == MANAGER:
        return Project.objects.filter(Q(project_manager=user) | Q(created_by=user))
    return Project.objects.none()


def visible_projects(user):
    from apps.projects.models import Project

    role = get_role(user)
    if role == SUPER_ADMIN:
        return Project.objects.all()
    if role == MANAGER:
        return Project.objects.filter(
            Q(project_manager=user) | Q(created_by=user) | Q(team_members=user)
        ).distinct()
    return Project.objects.filter(team_members=user).distinct()


def managed_tasks(user):
    from apps.tasks.models import Task

    return Task.objects.filter(project__in=managed_projects(user))


def visible_tasks(user):
    from apps.tasks.models import Task

    role = get_role(user)
    if role == SUPER_ADMIN:
        return Task.objects.all()
    if role == MANAGER:
        return Task.objects.filter(
            Q(project__in=managed_projects(user)) | Q(assigned_to=user)
        ).distinct()
    return Task.objects.filter(assigned_to=user)


def managed_time_entries(user):
    """Time entries on projects the user manages."""
    from apps.time_tracking.models import TimeEntry

    return TimeEntry.objects.filter(task__project__in=managed_projects(user))


def visible_time_entries(user):
    from apps.time_tracking.models import TimeEntry

    if get_role(user) in (SUPER_ADMIN, MANAGER):
        return TimeEntry.objects.filter(
            Q(task__project__in=managed_projects(user)) | Q(user=user)
        ).distinct()
    return TimeEntry.objects.filter(user=user)
