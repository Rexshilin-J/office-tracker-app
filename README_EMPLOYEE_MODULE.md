# OfficeTracker – Employee module (drop-in overlay)

Copy `mobile/` and `backend/` over your projects (same relative paths).
No new Flutter packages. No Admin screen files are modified.

## Deploy order
1. Backend:  `python manage.py migrate`   (adds 2 tables: ExpenseClaim, Announcement/Notification – additive only)
2. Restart/redeploy the Render service.
3. Flutter:  `flutter pub get && flutter analyze && flutter run`

## Admin-side (Django admin site, /admin/)
* Expense claims → "Expense claims": select + "Approve selected pending claims",
  or open a claim, set Status = Rejected and write the reason.
* Announcements → add one; every active user receives it as a notification.

## Files changed in existing code (everything else is new)
* mobile/lib/features/employee/employee_home.dart  – only the EmployeeHome class replaced;
  TodayTab / TimeLogTab / MyDayView (used by Admin "My Day") are byte-identical.
* mobile/lib/core/session.dart – logout now also revokes the token on the server.
* backend: additive routes/views in accounts, attendance, expenses; app registered in settings + urls.
