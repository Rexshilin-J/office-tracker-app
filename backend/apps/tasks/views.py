from rest_framework import generics
from rest_framework.authentication import TokenAuthentication
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated

from apps.accounts.permissions import (
    MANAGER,
    SUPER_ADMIN,
    capability,
    get_role,
    managed_projects,
    visible_tasks,
)

from .serializers import TaskSerializer


def base_queryset(user):
    return visible_tasks(user).select_related("project", "assigned_to")


class TaskListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = TaskSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        queryset = base_queryset(self.request.user)
        params = self.request.query_params

        for field in ("project", "status", "priority"):
            if params.get(field):
                queryset = queryset.filter(**{field: params[field]})

        # Plain employees only ever see their own tasks anyway.
        if params.get("assigned_to") and get_role(self.request.user) in (
            SUPER_ADMIN,
            MANAGER,
        ):
            queryset = queryset.filter(assigned_to=params["assigned_to"])

        return queryset

    def get_permissions(self):
        if self.request.method == "POST":
            return [capability("manage_work")()]
        return [IsAuthenticated()]

    def perform_create(self, serializer):
        project = serializer.validated_data["project"]
        if not managed_projects(self.request.user).filter(pk=project.pk).exists():
            raise PermissionDenied("You can only add tasks to projects you manage.")
        serializer.save(created_by=self.request.user)


class TaskDetailAPIView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = TaskSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return base_queryset(self.request.user)

    def _can_manage(self, task):
        return managed_projects(self.request.user).filter(pk=task.project_id).exists()

    def perform_update(self, serializer):
        if not self._can_manage(serializer.instance):
            # Everyone else may only change the status of their own task.
            extra = set(self.request.data.keys()) - {"status"}
            if extra or serializer.instance.assigned_to_id != self.request.user.id:
                raise PermissionDenied("You can only update the status of your own tasks.")
        serializer.save()

    def perform_destroy(self, instance):
        if not self._can_manage(instance):
            raise PermissionDenied("You cannot delete this task.")
        instance.delete()
