from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Notification
from .serializers import NotificationSerializer

AUTH = [TokenAuthentication]
PERMS = [IsAuthenticated]


def mine(request):
    return Notification.objects.filter(recipient=request.user)


class NotificationListAPIView(generics.ListAPIView):
    """GET /api/notifications/?unread=1 - my notifications, newest first (max 100)."""

    serializer_class = NotificationSerializer
    authentication_classes = AUTH
    permission_classes = PERMS
    pagination_class = None

    def get_queryset(self):
        qs = mine(self.request)
        if self.request.query_params.get("unread") in ("1", "true", "True"):
            qs = qs.filter(is_read=False)
        return qs[:100]


class UnreadCountAPIView(APIView):
    """GET /api/notifications/unread-count/ -> {"count": n}  (cheap; used for the bell)."""

    authentication_classes = AUTH
    permission_classes = PERMS

    def get(self, request):
        return Response({"count": mine(request).filter(is_read=False).count()})


class MarkReadAPIView(APIView):
    """POST /api/notifications/<id>/read/ - mark one of my notifications as read."""

    authentication_classes = AUTH
    permission_classes = PERMS

    def post(self, request, pk):
        note = get_object_or_404(mine(request), pk=pk)
        if not note.is_read:
            note.is_read = True
            note.save(update_fields=["is_read"])
        return Response(NotificationSerializer(note).data)


class MarkAllReadAPIView(APIView):
    """POST /api/notifications/read-all/ - mark all my notifications as read."""

    authentication_classes = AUTH
    permission_classes = PERMS

    def post(self, request):
        updated = mine(request).filter(is_read=False).update(is_read=True)
        return Response({"updated": updated})
