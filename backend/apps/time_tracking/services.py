from django.utils import timezone

from .models import TimeEntry


def stop_entry(entry, now=None):
    """Close a running/paused entry and store its final duration."""
    now = now or timezone.now()
    if entry.status == "PAUSED" and entry.paused_at:
        entry.paused_seconds += int((now - entry.paused_at).total_seconds())
        entry.paused_at = None
        end_for_duration = now
    else:
        end_for_duration = now

    total = int((end_for_duration - entry.started_at).total_seconds())
    entry.duration_seconds = max(0, total - entry.paused_seconds)
    entry.ended_at = now
    entry.status = "STOPPED"
    entry.save()
    return entry


def stop_active_timer_for(user, now=None):
    """Used by check-out so no timer is left running after the workday."""
    entry = (
        TimeEntry.objects.select_for_update()
        .filter(user=user, status__in=["RUNNING", "PAUSED"])
        .first()
    )
    if entry:
        stop_entry(entry, now)
    return entry
