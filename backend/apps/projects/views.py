
from django.db.models import Count, IntegerField, OuterRef, Q, Subquery, Sum, Value
from django.db.models.functions import Coalesce
from rest_framework import generics
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated

from apps.accounts.permissions import (
    MANAGER,
    capability,
    get_role,
    managed_projects,
    visible_projects,
)

from .models import Project
from .serializers import ProjectSerializer


def project_queryset(user, write=False):
    """Projects visible (or editable, if write) to the user, with summaries."""
    from apps.time_tracking.models import TimeEntry

    tracked = (
        TimeEntry.objects.filter(task__project=OuterRef("pk"), status="STOPPED")
        .values("task__project")
        .annotate(total=Sum("duration_seconds"))
        .values("total")
    )
    qs = managed_projects(user) if write else visible_projects(user)
    return (
        qs.select_related("client", "project_manager")
        .prefetch_related("team_members")
        .annotate(
            total_tasks_n=Count("tasks", distinct=True),
            completed_tasks_n=Count(
                "tasks", filter=Q(tasks__status="COMPLETED"), distinct=True
            ),
            tracked_n=Coalesce(
                Subquery(tracked, output_field=IntegerField()), Value(0)
            ),
        )
    )


class ProjectListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = ProjectSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return project_queryset(self.request.user)

    def get_permissions(self):
        if self.request.method == "POST":
            return [capability("manage_work")()]
        return [IsAuthenticated()]

    def perform_create(self, serializer):
        extra = {"created_by": self.request.user}
        # A manager who creates a project becomes its manager by default.
        if get_role(self.request.user) == MANAGER and not serializer.validated_data.get(
            "project_manager"
        ):
            extra["project_manager"] = self.request.user
        serializer.save(**extra)


class ProjectDetailAPIView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = ProjectSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        write = self.request.method in ("PUT", "PATCH", "DELETE")
        return project_queryset(self.request.user, write=write)

    def get_permissions(self):
        if self.request.method in ["PUT", "PATCH", "DELETE"]:
            return [capability("manage_work")()]
        return [IsAuthenticated()]
