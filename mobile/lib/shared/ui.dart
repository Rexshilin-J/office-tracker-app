import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../core/api.dart';

// ---------------------------------------------------------------- formatting

String fmtSeconds(int s) {
  if (s < 0) s = 0;
  final h = (s ~/ 3600).toString().padLeft(2, '0');
  final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$h:$m:$sec';
}

String fmtHm(int s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

String todayStr() => DateTime.now().toIso8601String().substring(0, 10);

String daysAgoStr(int days) => DateTime.now()
    .subtract(Duration(days: days))
    .toIso8601String()
    .substring(0, 10);

String fmtTime(dynamic iso) {
  if (iso == null) return '--';
  final d = DateTime.tryParse(iso.toString())?.toLocal();
  if (d == null) return '--';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String pretty(String v) => v
    .split('_')
    .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
    .join(' ');

// ------------------------------------------------------------------- status

const Map<String, Set<String>> taskTransitions = {
  'TODO': {'IN_PROGRESS'},
  'IN_PROGRESS': {'TODO', 'IN_REVIEW', 'COMPLETED'},
  'IN_REVIEW': {'IN_PROGRESS', 'COMPLETED'},
  'COMPLETED': {'IN_PROGRESS'},
};

Color statusColor(String s) {
  switch (s) {
    case 'TODO':
    case 'PLANNING':
      return Colors.blueGrey;
    case 'IN_PROGRESS':
    case 'RUNNING':
      return Colors.blue;
    case 'IN_REVIEW':
    case 'PAUSED':
    case 'ON_HOLD':
      return Colors.orange;
    case 'COMPLETED':
      return Colors.green;
    case 'CANCELLED':
      return Colors.red;
    case 'LOW':
      return Colors.teal;
    case 'MEDIUM':
      return Colors.indigo;
    case 'HIGH':
      return Colors.deepOrange;
    case 'URGENT':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

class StatusChip extends StatelessWidget {
  final String value;
  const StatusChip(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        pretty(value),
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ----------------------------------------------------------------- realtime

/// Auto-refreshes a screen every [pollInterval]. This is what makes the app
/// feel "live": data re-loads in the background without the user doing anything.
mixin LivePolling<T extends StatefulWidget> on State<T> {
  Timer? _pollTimer;
  Duration get pollInterval => const Duration(seconds: 8);

  Future<void> refresh();

  void startPolling() {
    refresh();
    _pollTimer = Timer.periodic(pollInterval, (_) => refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// A ticking HH:MM:SS clock. Server sends elapsed seconds; this keeps counting
/// every second locally while the timer is running.
class LiveDuration extends StatefulWidget {
  final int baseSeconds;
  final bool running;
  final DateTime fetchedAt;
  final TextStyle? style;

  const LiveDuration({
    super.key,
    required this.baseSeconds,
    required this.running,
    required this.fetchedAt,
    this.style,
  });

  @override
  State<LiveDuration> createState() => _LiveDurationState();
}

class _LiveDurationState extends State<LiveDuration> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.running) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var seconds = widget.baseSeconds;
    if (widget.running) {
      seconds += DateTime.now().difference(widget.fetchedAt).inSeconds;
    }
    return Text(
      fmtSeconds(seconds),
      style: widget.style ??
          const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
    );
  }
}

// ------------------------------------------------------------------ widgets

void snack(BuildContext context, String message, {bool error = true}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
}

Future<bool> confirm(BuildContext context, String title, String body) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class ErrorBanner extends StatelessWidget {
  final String message;
  const ErrorBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: Colors.red.shade900)),
          ),
        ],
      ),
    );
  }
}

/// Same colour, shifted a little in hue -> a lively two-tone gradient.
LinearGradient colorGradient(Color c) {
  final hsl = HSLColor.fromColor(c);
  final other = hsl.withHue((hsl.hue + 28) % 360).toColor();
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [c, other],
  );
}

/// AppBar with a coloured gradient background and white text/icons.
AppBar gradientAppBar({
  required Widget title,
  List<Widget>? actions,
  Color color = const Color(0xFF4F46E5),
}) {
  return AppBar(
    title: title,
    actions: actions,
    foregroundColor: Colors.white,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    titleTextStyle: const TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w800,
    ),
    flexibleSpace: Container(
      decoration: BoxDecoration(gradient: colorGradient(color)),
    ),
  );
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: colorGradient(color),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -18,
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
        ),
      );
}

// -------------------------------------------------------------- form dialog

enum FType { text, multiline, password, email, select, date, time, multi }

class Opt {
  final dynamic value;
  final String label;
  const Opt(this.value, this.label);
}

class FDef {
  final String key;
  final String label;
  final FType type;
  final List<Opt> options;
  final bool required;
  final dynamic initial;
  const FDef(
    this.key,
    this.label, {
    this.type = FType.text,
    this.options = const [],
    this.required = false,
    this.initial,
  });
}

/// Generic add/edit dialog. Returns the entered values, or null if cancelled.
/// Empty values are returned as null so callers can drop them.
///
/// If [onSubmit] is given, the dialog stays open while it runs. Return an error
/// message to show it inside the dialog (the user keeps what they typed), or
/// null to close the dialog successfully.
Future<Map<String, dynamic>?> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FDef> fields,
  Future<String?> Function(Map<String, dynamic> values)? onSubmit,
}) {
  final values = <String, dynamic>{
    for (final f in fields)
      f.key: f.initial ?? (f.type == FType.multi ? <dynamic>[] : null),
  };
  final formKey = GlobalKey<FormState>();
  var busy = false;
  String? errorText;

  return showDialog<Map<String, dynamic>>(
    barrierDismissible: false,
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Widget build(FDef f) {
          switch (f.type) {
            case FType.select:
              return DropdownButtonFormField<dynamic>(
                initialValue: values[f.key],
                isExpanded: true,
                decoration: InputDecoration(labelText: f.label),
                items: [
                  if (!f.required)
                    const DropdownMenuItem<dynamic>(
                      value: null,
                      child: Text('-- None --'),
                    ),
                  for (final o in f.options)
                    DropdownMenuItem<dynamic>(
                      value: o.value,
                      child: Text(o.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => values[f.key] = v),
                validator: (v) =>
                    f.required && v == null ? '${f.label} is required' : null,
              );
            case FType.date:
              final current = values[f.key] as String?;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(f.label),
                subtitle: Text(current ?? 'Select date'),
                trailing: current == null
                    ? const Icon(Icons.calendar_today, size: 18)
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => values[f.key] = null),
                      ),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.tryParse(current ?? '') ?? now,
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 5),
                  );
                  if (picked != null) {
                    setState(() => values[f.key] =
                        picked.toIso8601String().substring(0, 10));
                  }
                },
              );
            case FType.time:
              final current = values[f.key] as String?;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(f.label),
                subtitle: Text(current ?? 'Select time'),
                trailing: current == null
                    ? const Icon(Icons.access_time, size: 18)
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => values[f.key] = null),
                      ),
                onTap: () async {
                  final parts = (current ?? '09:00').split(':');
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(
                      hour: int.tryParse(parts[0]) ?? 9,
                      minute: int.tryParse(parts[1]) ?? 0,
                    ),
                  );
                  if (picked != null) {
                    final hh = picked.hour.toString().padLeft(2, '0');
                    final mm = picked.minute.toString().padLeft(2, '0');
                    setState(() => values[f.key] = '$hh:$mm');
                  }
                },
              );
            case FType.multi:
              final selected = (values[f.key] as List<dynamic>);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(f.label),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final o in f.options)
                        FilterChip(
                          label: Text(o.label),
                          selected: selected.contains(o.value),
                          onSelected: (on) => setState(() {
                            if (on) {
                              selected.add(o.value);
                            } else {
                              selected.remove(o.value);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              );
            default:
              return TextFormField(
                initialValue: values[f.key]?.toString(),
                obscureText: f.type == FType.password,
                keyboardType: f.type == FType.email
                    ? TextInputType.emailAddress
                    : (f.type == FType.multiline
                        ? TextInputType.multiline
                        : TextInputType.text),
                minLines: f.type == FType.multiline ? 2 : 1,
                maxLines: f.type == FType.multiline ? 5 : 1,
                decoration: InputDecoration(
                  labelText: f.label,
                  alignLabelWithHint: f.type == FType.multiline,
                ),
                onChanged: (v) => values[f.key] =
                    f.type == FType.password ? v : v.trim(),
                validator: (v) => f.required && (v == null || v.trim().isEmpty)
                    ? '${f.label} is required'
                    : null,
              );
          }
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < fields.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 8 : 16),
                        child: build(fields[i]),
                      ),
                    if (errorText != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          errorText!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final out = <String, dynamic>{};
                      values.forEach((k, v) {
                        out[k] = (v is String && v.isEmpty) ? null : v;
                      });
                      if (onSubmit == null) {
                        Navigator.pop(ctx, out);
                        return;
                      }
                      setState(() {
                        busy = true;
                        errorText = null;
                      });
                      final err = await onSubmit(out);
                      if (!ctx.mounted) return;
                      if (err == null) {
                        Navigator.pop(ctx, out);
                      } else {
                        setState(() {
                          busy = false;
                          errorText = err;
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}

/// Runs an API call, shows any error as a snackbar, returns true on success.
Future<bool> guarded(BuildContext context, Future<dynamic> Function() call) async {
  try {
    await call();
    return true;
  } on ApiException catch (e) {
    if (context.mounted) snack(context, e.message);
    return false;
  }
}

/// Builds an API payload from dialog values: nullable keys keep null (to clear
/// them), text keys become '' and everything else that is null is dropped.
Map<String, dynamic> cleanPayload(
  Map<String, dynamic> values, {
  Set<String> nullable = const {},
  Set<String> text = const {},
}) {
  final out = <String, dynamic>{};
  values.forEach((k, v) {
    if (v == null) {
      if (nullable.contains(k)) {
        out[k] = null;
      } else if (text.contains(k)) {
        out[k] = '';
      }
    } else {
      out[k] = v;
    }
  });
  return out;
}

const List<Opt> priorityOpts = [
  Opt('LOW', 'Low'),
  Opt('MEDIUM', 'Medium'),
  Opt('HIGH', 'High'),
  Opt('URGENT', 'Urgent'),
];

/// People who can work on projects/tasks. Super Admins never appear here.
/// With [managersOnly], only users whose role is Manager (for "Project manager").
List<Opt> employeeOpts(
  List<Map<String, dynamic>> employees, {
  bool managersOnly = false,
}) =>
    [
      for (final e in employees.where((e) =>
          e['is_active'] != false &&
          e['role'] != 'SUPER_ADMIN' &&
          (!managersOnly || e['role'] == 'MANAGER')))
        Opt(
          e['id'],
          '${e['username']}'
          '${(e['employee_id'] ?? '').toString().isEmpty ? '' : ' (${e['employee_id']})'}',
        ),
    ];


/// "2026-11-03" + "09:30" (device local time) -> UTC ISO string for the API.
String? localIso(String date, String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return null;
  final d = DateTime.tryParse(date);
  final parts = hhmm.split(':');
  if (d == null || parts.length < 2) return null;
  return DateTime(d.year, d.month, d.day, int.parse(parts[0]), int.parse(parts[1]))
      .toUtc()
      .toIso8601String();
}

/// API ISO datetime -> "HH:mm" in device local time (for form initial values).
String? hhmmOf(dynamic iso) {
  final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  if (d == null) return null;
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}


/// Form dialog that sends data to the server and stays open on errors.
/// Returns true when the server accepted the data.
Future<bool> showSubmitForm(
  BuildContext context, {
  required String title,
  required List<FDef> fields,
  required Future<dynamic> Function(Map<String, dynamic> values) submit,
}) async {
  final result = await showFormDialog(
    context,
    title: title,
    fields: fields,
    onSubmit: (values) async {
      try {
        await submit(values);
        return null;
      } on ApiException catch (e) {
        return e.message;
      }
    },
  );
  return result != null;
}
