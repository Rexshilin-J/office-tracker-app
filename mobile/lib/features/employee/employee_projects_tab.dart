import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';
import 'employee_tasks_tab.dart' show TaskDetailScreen;
import 'employee_widgets.dart';

// ====================================================================== LIST

/// "My Projects": projects the logged-in employee is a team member of.
class MyProjectsTab extends StatefulWidget {
  const MyProjectsTab({super.key});

  @override
  State<MyProjectsTab> createState() => _MyProjectsTabState();
}

class _MyProjectsTabState extends State<MyProjectsTab>
    with LivePolling<MyProjectsTab> {
  List<Map<String, dynamic>> projects = [];
  String filter = 'ALL';
  String? error;
  bool loaded = false;

  static const List<String> _filters = [
    'ALL',
    'PLANNING',
    'IN_PROGRESS',
    'ON_HOLD',
    'COMPLETED',
    'CANCELLED',
  ];

  @override
  Duration get pollInterval => const Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> refresh() async {
    try {
      final data = await Api.instance.get('/api/projects/');
      if (!mounted) return;
      setState(() {
        projects = asMapList(data);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _open(Map<String, dynamic> p) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyProjectDetailScreen(projectId: asInt(p['id'])),
      ),
    );
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final shown = filter == 'ALL'
        ? projects
        : projects.where((p) => p['status'] == filter).toList();

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final s in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s == 'ALL' ? 'All' : pretty(s)),
                    selected: filter == s,
                    onSelected: (_) => setState(() => filter = s),
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
                        ? 'You are not assigned to any project yet.'
                        : 'No ${pretty(filter).toLowerCase()} projects.',
                  ),
                for (final p in shown)
                  EmpProjectCard(project: p, onTap: () => _open(p)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==================================================================== DETAIL

/// Read-only project page for an employee (editing is a manager/admin job).
class MyProjectDetailScreen extends StatefulWidget {
  final int projectId;
  const MyProjectDetailScreen({super.key, required this.projectId});

  @override
  State<MyProjectDetailScreen> createState() => _MyProjectDetailScreenState();
}

class _MyProjectDetailScreenState extends State<MyProjectDetailScreen>
    with LivePolling<MyProjectDetailScreen> {
  static const Color _color = Color(0xFF2563EB);

  Map<String, dynamic>? project;
  List<Map<String, dynamic>> myTasks = [];
  String? error;

  @override
  Duration get pollInterval => const Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> refresh() async {
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.get('/api/projects/${widget.projectId}/'),
        Api.instance.get('/api/tasks/', query: {'project': '${widget.projectId}'}),
      ]);
      if (!mounted) return;
      setState(() {
        project = asMap(r[0]);
        myTasks = asMapList(r[1]);
        error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _openTask(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TaskDetailScreen(taskId: id)),
    );
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = project;
    return Scaffold(
      appBar: gradientAppBar(title: const Text('Project'), color: _color),
      body: p == null
          ? Center(
              child: error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(error!, textAlign: TextAlign.center),
                    )
                  : const CircularProgressIndicator(),
            )
          : RefreshIndicator(onRefresh: refresh, child: _content(p)),
    );
  }

  Widget _content(Map<String, dynamic> p) {
    final status = asText(p['status'], 'PLANNING');
    final finished = status == 'COMPLETED' || status == 'CANCELLED';
    final progress = asInt(p['progress_percent']);
    final due = dueInfo(p['deadline'], done: finished);
    final overdue = p['is_overdue'] == true;
    final accent = overdue ? Colors.red : statusColor(status);
    final description = asText(p['description']);
    final team = asMapList(p['team_members_detail']);
    final open = myTasks.where((t) => t['status'] != 'COMPLETED').toList()
      ..sort(compareByDue);
    final done = myTasks.where((t) => t['status'] == 'COMPLETED').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null) ErrorBanner(error!),
        Text(
          asText(p['name']),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            StatusChip(status),
            StatusChip(asText(p['priority'], 'MEDIUM')),
            if (overdue)
              const Chip(
                label: Text('Overdue'),
                visualDensity: VisualDensity.compact,
                backgroundColor: Color(0xFFFFEBEE),
                labelStyle: TextStyle(color: Colors.red, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Progress  •  $progress%',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress / 100,
                  color: accent,
                  backgroundColor: accent.withValues(alpha: 0.15),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 6),
                Text(
                  '${asInt(p['completed_tasks'])} of ${asInt(p['total_tasks'])} tasks completed',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                _row(Icons.business, 'Client', asText(p['client_name'], 'No client')),
                _row(Icons.person_outline, 'Manager',
                    asText(p['project_manager_name'], '-')),
                _row(Icons.play_circle_outline, 'Start date',
                    p['start_date'] == null ? 'Not set' : fmtDay(p['start_date'])),
                _row(
                  Icons.event,
                  'Deadline',
                  due == null ? 'Not set' : '${fmtDay(p['deadline'])}  (${due.text})',
                  valueColor: due?.color,
                ),
                _row(Icons.timer_outlined, 'Time tracked',
                    fmtHm(asInt(p['tracked_seconds']))),
              ],
            ),
          ),
        ),
        if (description.isNotEmpty) ...[
          const SectionHeader('About'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(width: double.infinity, child: Text(description)),
            ),
          ),
        ],
        SectionHeader('Team (${team.length})'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: team.isEmpty
                ? const Text('No team members.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in team)
                        Chip(
                          avatar: CircleAvatar(
                            child: Text(
                              asText(m['username'], '?').substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          label: Text(asText(m['username'])),
                        ),
                    ],
                  ),
          ),
        ),
        SectionHeader('My tasks here (${myTasks.length})'),
        if (myTasks.isEmpty)
          const EmptyState('No tasks assigned to you in this project.'),
        for (final t in [...open, ...done])
          EmpTaskCard(task: t, onTap: () => _openTask(asInt(t['id']))),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
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
}
