import os

from django.conf import settings
from django.http import HttpResponse


class SimpleCorsMiddleware:
    """
    Minimal CORS support so the Flutter web app (different port) can call the API.
    Set DJANGO_CORS_ORIGINS="https://app.example.com,https://admin.example.com"
    in production. With DEBUG=True and nothing set, all origins are allowed.
    """

    def __init__(self, get_response):
        self.get_response = get_response
        raw = os.getenv("DJANGO_CORS_ORIGINS", "")
        self.origins = [o.strip() for o in raw.split(",") if o.strip()]

    def allowed(self, origin):
        if not origin:
            return False
        if self.origins:
            return origin in self.origins
        return settings.DEBUG

    def __call__(self, request):
        origin = request.headers.get("Origin")
        if request.method == "OPTIONS" and origin:
            response = HttpResponse(status=200)
        else:
            response = self.get_response(request)

        if self.allowed(origin):
            response["Access-Control-Allow-Origin"] = origin
            response["Vary"] = "Origin"
            response["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
            response["Access-Control-Allow-Methods"] = "GET, POST, PATCH, PUT, DELETE, OPTIONS"
        return response
