import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';
import 'employee_attendance_tab.dart';
import 'employee_dashboard_tab.dart';
import 'employee_expenses_tab.dart';
import 'employee_notifications.dart';
import 'employee_profile_screen.dart';
import 'employee_projects_tab.dart';
import 'employee_tasks_tab.dart';

class _EmpTab {
  final String label;
  final IconData icon;
  final Color color;
  final Widget Function() build;
  const _EmpTab(this.label, this.icon, this.color, this.build);
}

/// The employee app: Home, Tasks, Projects, Attendance and Expenses tabs, with
/// Notifications, Profile and Logout in the app bar. Like the admin app, only
/// the visible tab is built (and polls the server).
class EmployeeHome extends StatefulWidget {
  final Session session;
  const EmployeeHome({super.key, required this.session});

  @override
  State<EmployeeHome> createState() => _EmployeeHomeState();
}

class _EmployeeHomeState extends State<EmployeeHome> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// If the session ends (logout, or the server rejects the token) while a
  /// detail screen is open, close those screens so Login is what you see.
  void _onSessionChanged() {
    if (!widget.session.loggedIn && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  List<_EmpTab> _tabs() => [
        _EmpTab(
          'Home',
          Icons.dashboard_rounded,
          const Color(0xFF4F46E5),
          () => EmployeeDashboardTab(
            session: widget.session,
            onGoToTab: (i) => setState(() => _index = i),
          ),
        ),
        _EmpTab('Tasks', Icons.task_alt_rounded, const Color(0xFF0D9488),
            () => const MyTasksTab()),
        _EmpTab('Projects', Icons.folder_rounded, const Color(0xFF2563EB),
            () => const MyProjectsTab()),
        _EmpTab('Attendance', Icons.event_available_rounded,
            const Color(0xFF16A34A), () => const MyAttendanceTab()),
        _EmpTab('Expenses', Icons.receipt_long_rounded, const Color(0xFFF97316),
            () => const MyExpensesTab()),
      ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final tab = tabs[_index];

    return Scaffold(
      appBar: gradientAppBar(
        color: tab.color,
        title: Text(_index == 0 ? 'Hi, ${widget.session.username}' : tab.label),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'My profile',
            icon: const Icon(Icons.account_circle_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MyProfileScreen(session: widget.session),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              if (await confirm(context, 'Logout', 'Logout pannanuma?')) {
                widget.session.logout();
              }
            },
          ),
        ],
      ),
      body: KeyedSubtree(key: ValueKey(tab.label), child: tab.build()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        indicatorColor: tab.color.withValues(alpha: 0.16),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon, color: t.color.withValues(alpha: 0.55)),
              selectedIcon: Icon(t.icon, color: t.color),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

// ===================================================================== TODAY

class TodayTab extends StatefulWidget {
  const TodayTab({super.key});

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> with LivePolling<TodayTab> {
  Map<String, dynamic> attendance = {};
  Map<String, dynamic>? active;
  List<Map<String, dynamic>> tasks = [];
  DateTime fetchedAt = DateTime.now();
  String? error;
  bool loaded = false;
  bool busy = false;

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
        Api.instance.get('/api/tasks/', query: {
          if (Api.instance.userId != null)
            'assigned_to': Api.instance.userId.toString(),
        }),
      ]);
      if (!mounted) return;
      final activeData = asMap(r[1]);
      setState(() {
        attendance = asMap(r[0]);
        active = activeData['entry'] == null ? null : asMap(activeData['entry']);
        tasks = asMapList(r[2]);
        fetchedAt = DateTime.now();
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _run(Future<dynamic> Function() call) async {
    setState(() => busy = true);
    await guarded(context, call);
    await refresh();
    if (mounted) setState(() => busy = false);
  }

  bool get checkedIn => attendance['checked_in'] == true;
  bool get checkedOut => attendance['checked_out'] == true;

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final open = tasks.where((t) => t['status'] != 'COMPLETED').toList();
    final done = tasks.where((t) => t['status'] == 'COMPLETED').toList();

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null) ErrorBanner(error!),
          _attendanceCard(),
          const SizedBox(height: 12),
          _timerCard(),
          const SizedBox(height: 20),
          Text('My Tasks (${open.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (open.isEmpty) const EmptyState('Assigned open tasks illa.'),
          for (final t in open) _taskCard(t),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Completed (${done.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final t in done) _taskCard(t),
          ],
        ],
      ),
    );
  }

  Widget _attendanceCard() {
    String statusText;
    Color color;
    if (!checkedIn) {
      statusText = 'Not checked in';
      color = Colors.grey;
    } else if (!checkedOut) {
      statusText = 'Working since ${fmtTime(attendance['check_in'])}';
      color = Colors.green;
    } else {
      statusText =
          'Done: ${fmtTime(attendance['check_in'])} - ${fmtTime(attendance['check_out'])}'
          ' (${fmtHm((attendance['worked_seconds'] ?? 0) as int)})';
      color = Colors.indigo;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
                  const Text('Attendance',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(statusText, style: TextStyle(color: color)),
                ],
              ),
            ),
            if (!checkedIn)
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => _run(() => Api.instance
                        .post('/api/attendance/', {'action': 'check_in'})),
                icon: const Icon(Icons.login),
                label: const Text('Check in'),
              )
            else if (!checkedOut)
              FilledButton.tonalIcon(
                onPressed: busy
                    ? null
                    : () async {
                        final ok = await confirm(
                          context,
                          'Check out',
                          'Check out pannina running timer-um stop aagum. Continue?',
                        );
                        if (ok) {
                          _run(() => Api.instance.post(
                              '/api/attendance/', {'action': 'check_out'}));
                        }
                      },
                icon: const Icon(Icons.logout),
                label: const Text('Check out'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _timerCard() {
    final entry = active;
    if (entry == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  checkedIn && !checkedOut
                      ? 'Timer illa. Task-la Start click pannunga.'
                      : 'Timer start panna mudhalla check in pannunga.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final running = entry['status'] == 'RUNNING';
    return Card(
      color: running ? Colors.blue.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                StatusChip(entry['status'] as String),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry['task_title']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LiveDuration(
              baseSeconds: (entry['elapsed_seconds'] ?? 0) as int,
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
                    onPressed: busy
                        ? null
                        : () => _run(() => Api.instance
                            .post('/api/time-tracking/', {'action': 'pause'})),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  )
                else
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => _run(() => Api.instance
                            .post('/api/time-tracking/', {'action': 'resume'})),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: busy
                      ? null
                      : () => _run(() => Api.instance
                          .post('/api/time-tracking/', {'action': 'stop'})),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> t) {
    final status = t['status'] as String;
    final isActive = active != null && active!['task'] == t['id'];
    final canStart = checkedIn &&
        !checkedOut &&
        active == null &&
        status != 'COMPLETED';
    final next = taskTransitions[status] ?? <String>{};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t['title']?.toString() ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                StatusChip(status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${t['project_name']}'
              '${t['due_date'] != null ? '  •  Due ${t['due_date']}' : ''}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            if ((t['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(t['description'].toString()),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                StatusChip(t['priority'] as String),
                const Spacer(),
                if (isActive)
                  const Text('Timer running',
                      style: TextStyle(color: Colors.blue)),
                if (canStart)
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => _run(() => Api.instance.post(
                            '/api/time-tracking/',
                            {'action': 'start', 'task': t['id']})),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start'),
                  ),
                if (next.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Change status',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (s) => _run(() => Api.instance
                        .patch('/api/tasks/${t['id']}/', {'status': s})),
                    itemBuilder: (_) => [
                      for (final s in next)
                        PopupMenuItem(
                          value: s,
                          child: Text(s == 'IN_REVIEW'
                              ? 'Submit for review'
                              : (s == 'COMPLETED'
                                  ? 'Mark complete'
                                  : 'Move to ${pretty(s)}')),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================== TIME LOG

class TimeLogTab extends StatefulWidget {
  const TimeLogTab({super.key});

  @override
  State<TimeLogTab> createState() => _TimeLogTabState();
}

class _TimeLogTabState extends State<TimeLogTab> with LivePolling<TimeLogTab> {
  List<Map<String, dynamic>> entries = [];
  DateTime fetchedAt = DateTime.now();
  String? error;
  bool loaded = false;

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
      final data = await Api.instance
          .get('/api/time-tracking/', query: {'date_from': daysAgoStr(6)});
      if (!mounted) return;
      setState(() {
        entries = asMapList(data);
        fetchedAt = DateTime.now();
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final today = todayStr();
    var todaySeconds = 0;
    for (final e in entries) {
      if (e['date'] == today) todaySeconds += (e['elapsed_seconds'] ?? 0) as int;
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null) ErrorBanner(error!),
          Card(
            child: ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('Tracked today'),
              trailing: Text(fmtHm(todaySeconds),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Last 7 days', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (entries.isEmpty) const EmptyState('Time entries illa.'),
          for (final e in entries)
            Card(
              child: ListTile(
                title: Text(e['task_title']?.toString() ?? ''),
                subtitle: Text(
                    '${e['date']}  •  ${fmtTime(e['started_at'])} - ${e['ended_at'] == null ? 'now' : fmtTime(e['ended_at'])}'),
                trailing: e['status'] == 'STOPPED'
                    ? Text(fmtHm((e['duration_seconds'] ?? 0) as int))
                    : LiveDuration(
                        baseSeconds: (e['elapsed_seconds'] ?? 0) as int,
                        running: e['status'] == 'RUNNING',
                        fetchedAt: fetchedAt,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}


/// "My Day" for HR / Manager: they also check in, track time and work on tasks.
class MyDayView extends StatelessWidget {
  const MyDayView({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: 'Today'), Tab(text: 'Time Log')]),
          Expanded(child: TabBarView(children: [TodayTab(), TimeLogTab()])),
        ],
      ),
    );
  }
}
