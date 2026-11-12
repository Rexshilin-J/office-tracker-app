"""
Creates notifications automatically when something relevant happens.

  * a task is assigned (or re-assigned) to someone
  * someone is added to a project's team
  * a project's status or deadline changes  -> its team + manager
  * an Announcement is posted               -> every active user

Everything here is best-effort: if creating a notification ever fails, the
original save (task, project, ...) must still succeed, so errors are logged
and swallowed inside their own savepoint.
"""
import logging

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models.signals import m2m_changed, post_save, pre_save
from django.dispatch import receiver

from apps.projects.models import Project
from apps.tasks.models import Task

from .models import Announcement, Notification

logger = logging.getLogger(__name__)

PROJECT_STATUS = dict(Project.STATUS_CHOICES)


def notify(user_ids, kind, title, message="", task=None, project=None):
    """Create one Notification per recipient id. Never raises."""
    user_ids = {uid for uid in user_ids if uid}
    if not user_ids:
        return
    try:
        with transaction.atomic():  # savepoint: a failure can't poison the caller
            Notification.objects.bulk_create(
                [
                    Notification(
                        recipient_id=uid,
                        kind=kind,
                        title=title,
                        message=message,
                        task=task,
                        project=project,
                    )
                    for uid in user_ids
                ]
            )
    except Exception:  # noqa: BLE001 - must never break the original save
        logger.exception("Could not create notifications (%s)", title)


# --------------------------------------------------------------------- tasks
@receiver(pre_save, sender=Task)
def remember_old_assignee(sender, instance, **kwargs):
    instance._old_assignee_id = (
        Task.objects.filter(pk=instance.pk).values_list("assigned_to_id", flat=True).first()
        if instance.pk
        else None
    )


@receiver(post_save, sender=Task)
def task_assigned(sender, instance, created, **kwargs):
    assignee = instance.assigned_to_id
    if not assignee:
        return
    if not created and getattr(instance, "_old_assignee_id", None) == assignee:
        return  # same person: this was an ordinary edit / status change
    if created and instance.created_by_id == assignee:
        return  # assigned a task to yourself - no need to notify
    message = f"{instance.title} - {instance.project.name}"
    if instance.due_date:
        message += f" (due {instance.due_date:%d %b %Y})"
    notify([assignee], "TASK", "New task assigned", message, task=instance, project=instance.project)


# ------------------------------------------------------------------ projects
@receiver(pre_save, sender=Project)
def remember_old_project_state(sender, instance, **kwargs):
    old = (
        Project.objects.filter(pk=instance.pk).values("status", "deadline").first()
        if instance.pk
        else None
    )
    instance._old_state = old


@receiver(post_save, sender=Project)
def project_updated(sender, instance, created, **kwargs):
    old = getattr(instance, "_old_state", None)
    if created or not old:
        return
    changes = []
    if old["status"] != instance.status:
        changes.append(
            f"Status: {PROJECT_STATUS.get(old['status'], old['status'])} -> "
            f"{PROJECT_STATUS.get(instance.status, instance.status)}"
        )
    if old["deadline"] != instance.deadline:
        was = f"{old['deadline']:%d %b %Y}" if old["deadline"] else "none"
        now = f"{instance.deadline:%d %b %Y}" if instance.deadline else "none"
        changes.append(f"Deadline: {was} -> {now}")
    if not changes:
        return
    recipients = set(instance.team_members.values_list("pk", flat=True))
    if instance.project_manager_id:
        recipients.add(instance.project_manager_id)
    notify(
        recipients,
        "PROJECT",
        f"Project updated: {instance.name}",
        "\n".join(changes),
        project=instance,
    )


@receiver(m2m_changed, sender=Project.team_members.through)
def added_to_project(sender, instance, action, reverse, pk_set, **kwargs):
    if action != "post_add" or reverse or not pk_set:
        return
    people = set(pk_set) - {instance.created_by_id}  # the creator knows already
    notify(
        people,
        "PROJECT",
        "You were added to a project",
        instance.name,
        project=instance,
    )


# ------------------------------------------------------------- announcements
@receiver(post_save, sender=Announcement)
def announcement_posted(sender, instance, created, **kwargs):
    if not created:
        return
    ids = get_user_model().objects.filter(is_active=True).values_list("pk", flat=True)
    notify(ids, "ANNOUNCEMENT", instance.title, instance.message)
