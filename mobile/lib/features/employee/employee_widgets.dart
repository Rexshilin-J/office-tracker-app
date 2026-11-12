import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';

// Building blocks shared by the employee screens (dashboard, tasks, projects,
// attendance ...). Nothing in here is used by the Admin screens.

// ---------------------------------------------------------------- parsing

/// JSON numbers may arrive as int, double or String - never crash on them.
int asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

String asText(dynamic v, [String fallback = '']) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? fallback : s;
}

// ------------------------------------------------------------------- dates

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "2026-11-09" -> "9 Nov 2026"
String fmtDay(dynamic ymd) {
  final d = DateTime.tryParse(asText(ymd));
  if (d == null) return '--';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// API timestamp ("2026-11-09T04:30:00Z") -> "9 Nov 2026" in device local time.
String fmtIsoDay(dynamic iso) {
  final d = DateTime.tryParse(asText(iso))?.toLocal();
  if (d == null) return '--';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// "2026-11-09" -> "Mon"
String fmtWeekday(dynamic ymd) {
  final d = DateTime.tryParse(asText(ymd));
  if (d == null) return '';
  return _weekdays[d.weekday - 1];
}

/// Whole days from today to a "YYYY-MM-DD" date. Negative = in the past.
int? daysUntil(dynamic ymd) {
  final d = DateTime.tryParse(asText(ymd));
  if (d == null) return null;
  final now = DateTime.now();
  return DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(now.year, now.month, now.day))
      .inDays;
}

class DueInfo {
  final String text;
  final Color color;
  const DueInfo(this.text, this.color);
}

/// Human wording + colour for a due date / deadline. Null when there is none.
DueInfo? dueInfo(dynamic ymd, {bool done = false}) {
  final n = daysUntil(ymd);
  if (n == null) return null;
  final day = fmtDay(ymd);
  if (done) return DueInfo('Due $day', Colors.grey.shade600);
  if (n < 0) {
    return DueInfo('Overdue by ${-n} day${n == -1 ? '' : 's'}', Colors.red);
  }
  if (n == 0) return DueInfo('Due today', Colors.deepOrange);
  if (n == 1) return DueInfo('Due tomorrow', Colors.orange.shade800);
  if (n <= 7) return DueInfo('Due in $n days', Colors.orange.shade800);
  return DueInfo('Due $day', Colors.grey.shade700);
}

/// ISO timestamp -> "5m ago", "3h ago", "2d ago", or a date.
String timeAgo(dynamic iso) {
  final d = DateTime.tryParse(asText(iso))?.toLocal();
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return fmtDay(d.toIso8601String().substring(0, 10));
}

// ----------------------------------------------------------------- headers

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- attendance

/// Today's attendance with Check in / Check out and a live "worked so far" clock.
class AttendanceStatusCard extends StatelessWidget {
  final Map<String, dynamic> attendance;
  final DateTime fetchedAt;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const AttendanceStatusCard({
    super.key,
    required this.attendance,
    required this.fetchedAt,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) {
    final checkedIn = attendance['checked_in'] == true;
    final checkedOut = attendance['checked_out'] == true;

    final String statusText;
    final Color color;
    if (!checkedIn) {
      statusText = 'Not checked in yet';
      color = Colors.grey;
    } else if (!checkedOut) {
      statusText = 'Working since ${fmtTime(attendance['check_in'])}';
      color = Colors.green;
    } else {
      statusText = '${fmtTime(attendance['check_in'])} - '
          '${fmtTime(attendance['check_out'])}  •  '
          '${fmtHm(asInt(attendance['worked_seconds']))}';
      color = Colors.indigo;
    }

    final checkIn = DateTime.tryParse(asText(attendance['check_in']));
    final workedBase =
        checkIn == null ? 0 : fetchedAt.difference(checkIn).inSeconds;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(Icons.fingerprint, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Today's attendance",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(statusText, style: TextStyle(color: color)),
                    ],
                  ),
                ),
                if (checkedIn && !checkedOut)
                  LiveDuration(
                    baseSeconds: workedBase,
                    running: true,
                    fetchedAt: fetchedAt,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            if (!checkedIn) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : onCheckIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Check in'),
                ),
              ),
            ] else if (!checkedOut) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : onCheckOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Check out'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- timer

/// The running / paused timer with Pause, Resume and Stop. [entry] is the
/// `entry` object from GET /api/time-tracking/active/ (null = no timer).
class ActiveTimerCard extends StatelessWidget {
  final Map<String, dynamic>? entry;
  final DateTime fetchedAt;
  final bool busy;
  final bool canStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback? onOpenTask;

  const ActiveTimerCard({
    super.key,
    required this.entry,
    required this.fetchedAt,
    required this.busy,
    required this.canStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    this.onOpenTask,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  canStart
                      ? 'No timer running. Open a task and press Start.'
                      : 'Check in first, then you can start a task timer.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final status = asText(e['status'], 'RUNNING');
    final running = status == 'RUNNING';
    return Card(
      color: running ? Colors.blue.shade50 : Colors.orange.shade50,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenTask,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  StatusChip(status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      asText(e['task_title']),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LiveDuration(
                baseSeconds: asInt(e['elapsed_seconds']),
                running: running,
                fetchedAt: fetchedAt,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (running)
                    OutlinedButton.icon(
                      onPressed: busy ? null : onPause,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: busy ? null : onResume,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume'),
                    ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: busy ? null : onStop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- tasks

/// Button / menu wording for a status move (the server enforces which moves
/// are legal - see `taskTransitions` in shared/ui.dart).
String statusActionLabel(String from, String to) {
  if (from == 'COMPLETED') return 'Reopen task';
  switch (to) {
    case 'IN_REVIEW':
      return 'Submit for review';
    case 'COMPLETED':
      return 'Mark as completed';
    case 'IN_PROGRESS':
      return from == 'TODO' ? 'Start working' : 'Back to In Progress';
    case 'TODO':
      return 'Move back to To Do';
    default:
      return 'Move to ${pretty(to)}';
  }
}

/// Moves a task to [to]. If a timer is running on that task and it is being
/// completed, the timer is stopped first so no time keeps counting on a
/// finished task. Returns true when the server accepted the change.
Future<bool> changeTaskStatus(
  BuildContext context,
  Map<String, dynamic> task,
  String to, {
  Map<String, dynamic>? activeEntry,
}) async {
  final timerOnThisTask =
      activeEntry != null && asInt(activeEntry['task']) == asInt(task['id']);

  if (to == 'COMPLETED' && timerOnThisTask) {
    final stopped = await guarded(
      context,
      () => Api.instance.post('/api/time-tracking/', {'action': 'stop'}),
    );
    if (!stopped) return false;
  }
  if (!context.mounted) return false;
  return guarded(
    context,
    () => Api.instance.patch('/api/tasks/${task['id']}/', {'status': to}),
  );
}

class EmpTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final bool timerActive;
  final VoidCallback onTap;

  /// When given, a "..." menu with the allowed status moves is shown.
  final ValueChanged<String>? onStatus;

  const EmpTaskCard({
    super.key,
    required this.task,
    required this.onTap,
    this.timerActive = false,
    this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    final status = asText(task['status'], 'TODO');
    final done = status == 'COMPLETED';
    final due = dueInfo(task['due_date'], done: done);
    final overdue = !done && (daysUntil(task['due_date']) ?? 0) < 0;
    final accent = overdue ? Colors.red : statusColor(status);
    final next = taskTransitions[status] ?? <String>{};

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 6)),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [accent.withValues(alpha: 0.07), Colors.white],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        asText(task['title']),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ),
                  if (onStatus != null && next.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: 'Change status',
                      icon: const Icon(Icons.more_vert),
                      onSelected: onStatus,
                      itemBuilder: (_) => [
                        for (final s in next)
                          PopupMenuItem<String>(
                            value: s,
                            child: Text(statusActionLabel(status, s)),
                          ),
                      ],
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
              Text(
                asText(task['project_name']),
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(status),
                    StatusChip(asText(task['priority'], 'MEDIUM')),
                    if (timerActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer, size: 13, color: Colors.blue),
                            SizedBox(width: 4),
                            Text(
                              'Timer on',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (due != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.event, size: 14, color: due.color),
                      const SizedBox(width: 4),
                      Text(
                        due.text,
                        style: TextStyle(
                          color: due.color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- projects

class EmpProjectCard extends StatelessWidget {
  final Map<String, dynamic> project;
  final VoidCallback onTap;

  const EmpProjectCard({super.key, required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = asText(project['status'], 'PLANNING');
    final finished = status == 'COMPLETED' || status == 'CANCELLED';
    final overdue = project['is_overdue'] == true;
    final progress = asInt(project['progress_percent']);
    final due = dueInfo(project['deadline'], done: finished);
    final accent = overdue ? Colors.red : statusColor(status);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 6)),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [accent.withValues(alpha: 0.07), Colors.white],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                asText(project['name']),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(
                '${asText(project['client_name'], 'No client')}'
                '  •  Manager: ${asText(project['project_manager_name'], '-')}',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  StatusChip(status),
                  StatusChip(asText(project['priority'], 'MEDIUM')),
                  if (overdue)
                    const Chip(
                      label: Text('Overdue'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Color(0xFFFFEBEE),
                      labelStyle: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress / 100,
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.15),
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${asInt(project['completed_tasks'])}/'
                      '${asInt(project['total_tasks'])} tasks  •  $progress%',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                  if (due != null)
                    Text(
                      due.text,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: due.color,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- sorting

const Map<String, int> _priorityRank = {
  'URGENT': 0,
  'HIGH': 1,
  'MEDIUM': 2,
  'LOW': 3,
};

/// Soonest due date first (no date = last), then most urgent first.
int compareByDue(Map<String, dynamic> a, Map<String, dynamic> b) {
  final da = asText(a['due_date']);
  final db = asText(b['due_date']);
  if (da.isEmpty != db.isEmpty) return da.isEmpty ? 1 : -1;
  final byDate = da.compareTo(db);
  if (byDate != 0) return byDate;
  return (_priorityRank[asText(a['priority'])] ?? 2)
      .compareTo(_priorityRank[asText(b['priority'])] ?? 2);
}
