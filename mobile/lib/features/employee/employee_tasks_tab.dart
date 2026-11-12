import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';
import 'employee_widgets.dart';

// ====================================================================== LIST

/// "My Tasks": every task assigned to the logged-in employee.
class MyTasksTab extends StatefulWidget {
  const MyTasksTab({super.key});

  @override
  State<MyTasksTab> createState() => _MyTasksTabState();
}

class _MyTasksTabState extends State<MyTasksTab> with LivePolling<MyTasksTab> {
  List<Map<String, dynamic>> tasks = [];
  Map<String, dynamic>? active;
  String filter = 'ALL';
  String? error;
  bool loaded = false;
  bool busy = false;

  static const List<String> _filters = [
    'ALL',
    'TODO',
    'IN_PROGRESS',
    'IN_REVIEW',
    'COMPLETED',
  ];

  @override
  Duration get pollInterval => const Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> refresh() async {
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.get('/api/tasks/'),
        Api.instance.get('/api/time-tracking/active/'),
      ]);
      if (!mounted) return;
      final activeData = asMap(r[1]);
      setState(() {
        tasks = asMapList(r[0]);
        active = activeData['entry'] == null ? null : asMap(activeData['entry']);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  int _count(String f) =>
      f == 'ALL' ? tasks.length : tasks.where((t) => t['status'] == f).length;

  /// Open tasks (soonest due first), then completed ones.
  List<Map<String, dynamic>> get _shown {
    final list =
        filter == 'ALL' ? tasks : tasks.where((t) => t['status'] == filter).toList();
    final open = list.where((t) => t['status'] != 'COMPLETED').toList()
      ..sort(compareByDue);
    final done = list.where((t) => t['status'] == 'COMPLETED').toList();
    return [...open, ...done];
  }

  Future<void> _changeStatus(Map<String, dynamic> t, String to) async {
    setState(() => busy = true);
    final ok = await changeTaskStatus(context, t, to, activeEntry: active);
    await refresh();
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      snack(
        context,
        to == 'COMPLETED' ? 'Task completed. Nice work!' : 'Status updated.',
        error: false,
      );
    }
  }

  Future<void> _open(Map<String, dynamic> t) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskDetailScreen(taskId: asInt(t['id'])),
      ),
    );
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final shown = _shown;

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${f == 'ALL' ? 'All' : pretty(f)} (${_count(f)})'),
                    selected: filter == f,
                    onSelected: (_) => setState(() => filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (error != null) ErrorBanner(error!),
                if (shown.isEmpty)
                  EmptyState(
                    filter == 'ALL'
                        ? 'No tasks assigned to you yet.'
                        : 'No ${pretty(filter).toLowerCase()} tasks.',
                  ),
                for (final t in shown)
                  EmpTaskCard(
                    task: t,
                    timerActive:
                        active != null && asInt(active!['task']) == asInt(t['id']),
                    onTap: () => _open(t),
                    onStatus: busy ? null : (s) => _changeStatus(t, s),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==================================================================== DETAIL

/// One task: details, status updates, and the task timer.
class TaskDetailScreen extends StatefulWidget {
  final int taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen>
    with LivePolling<TaskDetailScreen> {
  static const Color _color = Color(0xFF0D9488);

  Map<String, dynamic>? task;
  Map<String, dynamic>? active;
  Map<String, dynamic> attendance = {};
  List<Map<String, dynamic>> entries = [];
  DateTime fetchedAt = DateTime.now();
  String? error;
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
        Api.instance.get('/api/tasks/${widget.taskId}/'),
        Api.instance.get('/api/time-tracking/active/'),
        Api.instance.get('/api/attendance/'),
        Api.instance.get('/api/time-tracking/', query: {'task': '${widget.taskId}'}),
      ]);
      if (!mounted) return;
      final activeData = asMap(r[1]);
      setState(() {
        task = asMap(r[0]);
        active = activeData['entry'] == null ? null : asMap(activeData['entry']);
        attendance = asMap(r[2]);
        entries = asMapList(r[3]);
        fetchedAt = DateTime.now();
        error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _run(Future<dynamic> Function() call, {String? okMessage}) async {
    setState(() => busy = true);
    final ok = await guarded(context, call);
    await refresh();
    if (!mounted) return;
    setState(() => busy = false);
    if (ok && okMessage != null) snack(context, okMessage, error: false);
  }

  Future<void> _timer(String action) => _run(
        () => Api.instance.post('/api/time-tracking/', {
          'action': action,
          if (action == 'start') 'task': widget.taskId,
        }),
        okMessage: switch (action) {
          'start' => 'Timer started.',
          'pause' => 'Timer paused.',
          'resume' => 'Timer resumed.',
          _ => 'Timer stopped.',
        },
      );

  Future<void> _status(String to) async {
    final t = task;
    if (t == null) return;
    setState(() => busy = true);
    final ok = await changeTaskStatus(context, t, to, activeEntry: active);
    await refresh();
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      snack(
        context,
        to == 'COMPLETED' ? 'Task completed. Nice work!' : 'Status updated.',
        error: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = task;
    return Scaffold(
      appBar: gradientAppBar(title: const Text('Task'), color: _color),
      body: t == null
          ? Center(
              child: error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(error!, textAlign: TextAlign.center),
                    )
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(onRefresh: refresh, child: _content(t)),
    );
  }

  Widget _content(Map<String, dynamic> t) {
    final status = asText(t['status'], 'TODO');
    final done = status == 'COMPLETED';
    final due = dueInfo(t['due_date'], done: done);
    final description = asText(t['description']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null) ErrorBanner(error!),
        Text(
          asText(t['title']),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            StatusChip(status),
            StatusChip(asText(t['priority'], 'MEDIUM')),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                _infoRow(Icons.folder_outlined, 'Project', asText(t['project_name'], '-')),
                _infoRow(
                  Icons.event,
                  'Due date',
                  due == null ? 'Not set' : due.text,
                  valueColor: due?.color,
                ),
                _infoRow(Icons.add_circle_outline, 'Assigned', fmtIsoDay(t['created_at'])),
                if (done)
                  _infoRow(Icons.check_circle_outline, 'Completed',
                      fmtIsoDay(t['completed_at'])),
              ],
            ),
          ),
        ),
        if (description.isNotEmpty) ...[
          const SectionHeader('Description'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(width: double.infinity, child: Text(description)),
            ),
          ),
        ],
        const SectionHeader('Task timer'),
        _timerSection(done),
        const SectionHeader('Status'),
        _statusSection(t, status),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w600, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- timer
  Widget _timerSection(bool done) {
    final entry = active;
    final onThisTask = entry != null && asInt(entry['task']) == widget.taskId;
    final onOtherTask = entry != null && !onThisTask;
    final checkedIn = attendance['checked_in'] == true;
    final checkedOut = attendance['checked_out'] == true;

    // Total on this task: stopped sessions are fixed, a RUNNING one keeps ticking.
    var totalBase = 0;
    var ticking = false;
    for (final e in entries) {
      totalBase += asInt(e['elapsed_seconds']);
      if (e['status'] == 'RUNNING') ticking = true;
    }

    Widget controls;
    if (onThisTask && entry != null) {
      final running = entry['status'] == 'RUNNING';
      controls = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (running)
            OutlinedButton.icon(
              onPressed: busy ? null : () => _timer('pause'),
              icon: const Icon(Icons.pause),
              label: const Text('Pause'),
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : () => _timer('resume'),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume'),
            ),
          const SizedBox(width: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: busy ? null : () => _timer('stop'),
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ],
      );
    } else if (done) {
      controls = _hint('Completed tasks cannot be timed. Reopen the task to track time.');
    } else if (onOtherTask && entry != null) {
      controls = _hint(
        'A timer is already running on "${asText(entry['task_title'])}". '
        'Stop it before starting this one.',
      );
    } else if (!checkedIn) {
      controls = _hint('Check in from the Home tab to start a timer.');
    } else if (checkedOut) {
      controls = _hint('You have checked out for today.');
    } else {
      controls = SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: busy ? null : () => _timer('start'),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start timer'),
        ),
      );
    }

    final running = onThisTask && entry != null && entry['status'] == 'RUNNING';
    return Card(
      color: onThisTask
          ? (running ? Colors.blue.shade50 : Colors.orange.shade50)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (onThisTask && entry != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(asText(entry['status'], 'RUNNING')),
              ),
              const SizedBox(height: 4),
              const Text('This session', style: TextStyle(color: Colors.grey)),
              LiveDuration(
                baseSeconds: asInt(entry['elapsed_seconds']),
                running: running,
                fetchedAt: fetchedAt,
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total time on this task',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                LiveDuration(
                  baseSeconds: totalBase,
                  running: ticking,
                  fetchedAt: fetchedAt,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${entries.length} work session${entries.length == 1 ? '' : 's'}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            controls,
          ],
        ),
      ),
    );
  }

  Widget _hint(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(color: Colors.grey.shade700)),
      );

  // ---------------------------------------------------------------- status
  Widget _statusSection(Map<String, dynamic> t, String status) {
    // Same rules the server enforces (see Task.ALLOWED_TRANSITIONS).
    final next = taskTransitions[status] ?? <String>{};
    final buttons = <Widget>[];

    if (next.contains('COMPLETED')) {
      buttons.add(
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: busy ? null : () => _status('COMPLETED'),
            icon: const Icon(Icons.check_circle),
            label: Text(statusActionLabel(status, 'COMPLETED')),
          ),
        ),
      );
    }
    for (final s in next.where((s) => s != 'COMPLETED')) {
      buttons.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: busy ? null : () => _status(s),
            child: Text(statusActionLabel(status, s)),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                const Text('Current status: '),
                StatusChip(status),
              ],
            ),
            if (status == 'TODO') ...[
              const SizedBox(height: 8),
              Text(
                'Start working on the task first. You can complete it once it is in progress.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              buttons[i],
            ],
          ],
        ),
      ),
    );
  }
}
