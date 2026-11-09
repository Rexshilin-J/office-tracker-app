from django.db import migrations


def admin_to_super_admin(apps, schema_editor):
    EmployeeProfile = apps.get_model("accounts", "EmployeeProfile")
    EmployeeProfile.objects.filter(role="ADMIN").update(role="SUPER_ADMIN")


def super_admin_to_admin(apps, schema_editor):
    EmployeeProfile = apps.get_model("accounts", "EmployeeProfile")
    EmployeeProfile.objects.filter(role="SUPER_ADMIN").update(role="ADMIN")


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0002_roles"),
    ]

    operations = [
        migrations.RunPython(admin_to_super_admin, super_admin_to_admin),
    ]
