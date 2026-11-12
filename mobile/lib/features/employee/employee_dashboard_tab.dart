import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';
import 'employee_projects_tab.dart' show MyProjectDetailScreen;
import 'employee_tasks_tab.dart' show TaskDetailScreen;
import 'employee_widgets.dart';

/// Home tab of the employee app: attendance, timer, today's hours, task and
/// project counts, what is due next. Everything comes from the live API.
class EmployeeDashboardTab extends StatefulWidget {
  final Session session;

  /// Lets "See all" buttons jump to another tab of EmployeeHome.
  final ValueChanged<int> onGoToTab;

  const EmployeeDashboardTab({
    super.key,
    required this.session,
    required this.onGoToTab,
  });

  @override
  State<EmployeeDashboardTab> createState() => _EmployeeDashboardTabState();
}

class _EmployeeDashboardTabState extends State<EmployeeDashboardTab>
    with LivePolling<EmployeeDashboardTab> {
  Map<String, dynamic> attendance = {};
  Map<String, dynamic>? active;
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> projects = [];
  List<Map<String, dynamic>> todayEntries = [];
  DateTime fetchedAt = DateTime.now();
  String? error;
  bool loaded = false;
  bool busy = false;

  @override
  Duration get pollInterval => const Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> refresh() async {
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.get('/api/attendance/'),
        Api.instance.get('/api/time-tracking/active/'),
        Api.instance.get('/api/tasks/'),
        Api.instance.get('/api/projects/'),
        Api.instance.get('/api/time-tracking/', query: {'date_from': todayStr()}),
      ]);
      if (!mounted) return;
      final activeData = asMap(r[1]);
      setState(() {
        attendance = asMap(r[0]);
        active = activeData['entry'] == null ? null : asMap(activeData['entry']);
        tasks = asMapList(r[2]);
        projects = asMapList(r[3]);
        todayEntries = asMapList(r[4]);
        fetchedAt = DateTime.now();
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  /// Runs one API action, then reloads so the screen shows the new truth.
  Future<void> _run(Future<dynamic> Function() call) async {
    setState(() => busy = true);
    await guarded(context, call);
    await refresh();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _checkOut() async {
    final ok = await confirm(
      context,
      'Check out',
      'Checking out will also stop any running timer. Continue?',
    );
    if (ok) {
      await _run(
        () => Api.instance.post('/api/attendance/', {'action': 'check_out'}),
      );
    }
  }

  Future<void> _openTask(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TaskDetailScreen(taskId: id)),
    );
    if (mounted) refresh();
  }

  Future<void> _openProject(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyProjectDetailScreen(projectId: id),
      ),
    );
    if (mounted) refresh();
  }

  bool _isOverdue(Map<String, dynamic> t) =>
      t['status'] != 'COMPLETED' && (daysUntil(t['due_date']) ?? 0) < 0;

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final checkedIn = attendance['checked_in'] == true;
    final checkedOut = attendance['checked_out'] == true;

    final pending = tasks.where((t) => t['status'] != 'COMPLETED').toList()
      ..sort(compareByDue);
    final completed = tasks.where((t) => t['status'] == 'COMPLETED').length;
    final overdue = tasks.where(_isOverdue).length;
    final activeProjects = projects
        .where((p) => p['status'] != 'COMPLETED' && p['status'] != 'CANCELLED')
        .toList();

    // Time at work: since check-in while working, else the final worked time.
    final checkIn = DateTime.tryParse(asText(attendance['check_in']));
    final working = checkedIn && !checkedOut && checkIn != null;
    final workedBase = checkedOut
        ? asInt(attendance['worked_seconds'])
        : (checkIn == null ? 0 : fetchedAt.difference(checkIn).inSeconds);

    // Time tracked on tasks today: only a RUNNING entry keeps ticking.
    var trackedBase = 0;
    var tracking = false;
    for (final e in todayEntries) {
      trackedBase += asInt(e['elapsed_seconds']);
      if (e['status'] == 'RUNNING') tracking = true;
    }

    final width = MediaQuery.of(context).size.width;
    final cols = width > 900 ? 4 : 2;

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null) ErrorBanner(error!),
          AttendanceStatusCard(
            attendance: attendance,
            fetchedAt: fetchedAt,
            busy: busy,
            onCheckIn: () => _run(
              () => Api.instance.post('/api/attendance/', {'action': 'check_in'}),
            ),
            onCheckOut: _checkOut,
          ),
          const SizedBox(height: 4),
          ActiveTimerCard(
            entry: active,
            fetchedAt: fetchedAt,
            busy: busy,
            canStart: checkedIn && !checkedOut,
            onPause: () => _run(
              () => Api.instance.post('/api/time-tracking/', {'action': 'pause'}),
            ),
            onResume: () => _run(
              () => Api.instance.post('/api/time-tracking/', {'action': 'resume'}),
            ),
            onStop: () => _run(
              () => Api.instance.post('/api/time-tracking/', {'action': 'stop'}),
            ),
            onOpenTask:
                active == null ? null : () => _openTask(asInt(active!['task'])),
          ),
          const SizedBox(height: 4),
          _hoursCard(
            workedBase: workedBase,
            working: working,
            trackedBase: trackedBase,
            tracking: tracking,
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: cols == 2 ? 1.2 : 1.5,
            children: [
              StatCard(
                label: 'Pending tasks',
                value: '${pending.length}',
                icon: Icons.pending_actions,
                color: Colors.orange,
              ),
              StatCard(
                label: 'Completed tasks',
                value: '$completed',
                icon: Icons.task_alt,
                color: Colors.green,
              ),
              StatCard(
                label: 'Active projects',
                value: '${activeProjects.length}',
                icon: Icons.folder_rounded,
                color: Colors.blue,
              ),
              StatCard(
                label: 'Overdue tasks',
                value: '$overdue',
                icon: Icons.warning_amber,
                color: overdue > 0 ? Colors.red : Colors.blueGrey,
              ),
            ],
          ),
          SectionHeader(
            'Up next',
            actionLabel: pending.length > 3 ? 'All tasks' : null,
            onAction: () => widget.onGoToTab(1),
          ),
          if (pending.isEmpty) const EmptyState('No pending tasks. All clear!'),
          for (final t in pending.take(3))
            EmpTaskCard(
              task: t,
              timerActive: active != null && asInt(active!['task']) == asInt(t['id']),
              onTap: () => _openTask(asInt(t['id'])),
            ),
          SectionHeader(
            'My projects',
            actionLabel: activeProjects.length > 3 ? 'All projects' : null,
            onAction: () => widget.onGoToTab(2),
          ),
          if (activeProjects.isEmpty)
            const EmptyState('You are not assigned to any active project.'),
          for (final p in activeProjects.take(3))
            EmpProjectCard(
              project: p,
              onTap: () => _openProject(asInt(p['id'])),
            ),
        ],
      ),
    );
  }

  Widget _hoursCard({
    required int workedBase,
    required bool working,
    required int trackedBase,
    required bool tracking,
  }) {
    const accent = Color(0xFF4F46E5);
    const labelStyle = TextStyle(color: Colors.white70, fontSize: 13);
    const valueStyle = TextStyle(
      color: Colors.white,
      fontSize: 26,
      fontWeight: FontWeight.w800,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    Widget cell(String label, IconData icon, int base, bool running) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(label, style: labelStyle),
              ],
            ),
            const SizedBox(height: 6),
            LiveDuration(
              baseSeconds: base,
              running: running,
              fetchedAt: fetchedAt,
              style: valueStyle,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: colorGradient(accent),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's working hours",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              cell('At work', Icons.business_center, workedBase, working),
              cell('Tracked on tasks', Icons.timer, trackedBase, tracking),
            ],
          ),
        ],
      ),
    );
  }
}
