
from rest_framework import generics
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated

from apps.accounts.permissions import SUPER_ADMIN, capability, get_role

from .models import Client
from .serializers import ClientSerializer


class ClientListCreateAPIView(generics.ListCreateAPIView):
    serializer_class = ClientSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        queryset = Client.objects.all()

        if get_role(self.request.user) != SUPER_ADMIN:
            queryset = queryset.filter(is_active=True)

        return queryset

    def get_permissions(self):
        if self.request.method == "POST":
            return [capability("manage_clients")()]
        return [IsAuthenticated()]

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)


class ClientDetailAPIView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = ClientSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        queryset = Client.objects.all()

        if get_role(self.request.user) != SUPER_ADMIN:
            queryset = queryset.filter(is_active=True)

        return queryset

    def get_permissions(self):
        if self.request.method in ["PUT", "PATCH", "DELETE"]:
            return [capability("manage_clients")()]
        return [IsAuthenticated()]
