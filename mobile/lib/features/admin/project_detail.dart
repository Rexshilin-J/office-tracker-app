import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';
import 'project_form.dart';
import 'task_form.dart';

/// Full view of one project: details, progress, team and its tasks.
class ProjectDetailScreen extends StatefulWidget {
  final int projectId;
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> employees;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    required this.clients,
    required this.employees,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with LivePolling<ProjectDetailScreen> {
  Map<String, dynamic>? project;
  List<Map<String, dynamic>> tasks = [];
  String? error;
  bool deleted = false;

  @override
  Duration get pollInterval => const Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> refresh() async {
    if (deleted) return;
    try {
      final r = await Future.wait<dynamic>([
        Api.instance.get('/api/projects/${widget.projectId}/'),
        Api.instance.get('/api/tasks/',
            query: {'project': widget.projectId.toString()}),
      ]);
      if (!mounted) return;
      setState(() {
        project = asMap(r[0]);
        tasks = asMapList(r[1]);
        error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 404) {
        deleted = true;
        Navigator.pop(context);
        return;
      }
      setState(() => error = e.message);
    }
  }

  Future<void> _edit() async {
    final p = project;
    if (p == null) return;
    final saved = await showProjectForm(
      context,
      project: p,
      clients: widget.clients,
      employees: widget.employees,
    );
    if (saved) refresh();
  }

  Future<void> _delete() async {
    final p = project;
    if (p == null) return;
    if (!await confirm(context, 'Delete project',
        '"${p['name']}" and its ${p['total_tasks']} tasks delete aagum. Sure-a?')) {
      return;
    }
    if (!mounted) return;
    if (await guarded(
        context, () => Api.instance.delete('/api/projects/${p['id']}/'))) {
      deleted = true;
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _taskForm([Map<String, dynamic>? t]) async {
    final p = project;
    if (p == null) return;
    final saved = await showTaskForm(
      context,
      task: t,
      projects: [p],
      employees: widget.employees,
      projectId: p['id'] as int,
    );
    if (saved) refresh();
  }

  Future<void> _setStatus(Map<String, dynamic> t, String status) async {
    if (await guarded(context,
        () => Api.instance.patch('/api/tasks/${t['id']}/', {'status': status}))) {
      refresh();
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> t) async {
    if (!await confirm(context, 'Delete task', '"${t['title']}" delete pannanuma?')) {
      return;
    }
    if (!mounted) return;
    if (await guarded(
        context, () => Api.instance.delete('/api/tasks/${t['id']}/'))) {
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = project;
    return Scaffold(
      appBar: gradientAppBar(
        color: const Color(0xFF2563EB),
        title: Text(p?['name']?.toString() ?? 'Project'),
        actions: [
          IconButton(
              tooltip: 'Edit', icon: const Icon(Icons.edit), onPressed: _edit),
          IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete),
        ],
      ),
      floatingActionButton: p == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _taskForm(),
              icon: const Icon(Icons.add_task),
              label: const Text('Task'),
            ),
      body: p == null
          ? (error != null
              ? Padding(padding: const EdgeInsets.all(16), child: ErrorBanner(error!))
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  if (error != null) ErrorBanner(error!),
                  _header(p),
                  const SizedBox(height: 12),
                  _progress(p),
                  const SizedBox(height: 12),
                  _team(p),
                  const SizedBox(height: 20),
                  Text('Tasks (${tasks.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (tasks.isEmpty) const EmptyState('Intha project-la tasks illa.'),
                  for (final t in tasks) _taskCard(t),
                ],
              ),
            ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text('$label: ', style: TextStyle(color: Colors.grey.shade700)),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _header(Map<String, dynamic> p) {
    final overdue = p['is_overdue'] == true;
    final desc = (p['description'] ?? '').toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatusChip(p['status'] as String),
              StatusChip(p['priority'] as String),
              if (overdue)
                const Chip(
                  label: Text('Overdue'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Color(0xFFFFEBEE),
                  labelStyle: TextStyle(color: Colors.red, fontSize: 12),
                ),
            ]),
            const SizedBox(height: 10),
            _row(Icons.business, 'Client', (p['client_name'] ?? '-').toString()),
            _row(Icons.person, 'Manager',
                (p['project_manager_name'] ?? '-').toString()),
            _row(Icons.play_arrow, 'Start', (p['start_date'] ?? '-').toString()),
            _row(Icons.flag, 'Deadline', (p['deadline'] ?? '-').toString()),
            if (desc.isNotEmpty) ...[
              const Divider(height: 20),
              Text(desc),
            ],
          ],
        ),
      ),
    );
  }

  Widget _progress(Map<String, dynamic> p) {
    final percent = (p['progress_percent'] ?? 0) as int;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Progress',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('$percent%',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            Text(
              '${p['completed_tasks']}/${p['total_tasks']} tasks completed  •  '
              '${fmtHm((p['tracked_seconds'] ?? 0) as int)} tracked',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _team(Map<String, dynamic> p) {
    final members = asMapList(p['team_members_detail']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Team (${members.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (members.isEmpty)
              Text('Team members illa. Edit-la add pannunga.',
                  style: TextStyle(color: Colors.grey.shade600)),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in members)
                  Chip(
                    avatar: CircleAvatar(
                      child: Text(m['username'].toString()[0].toUpperCase(),
                          style: const TextStyle(fontSize: 11)),
                    ),
                    label: Text(m['username'].toString() +
                        (m['id'] == p['project_manager'] ? '  (Manager)' : '')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> t) {
    final nameOf = {for (final e in widget.employees) e['id']: e['username']};
    return Card(
      child: ListTile(
        onTap: () => _taskForm(t),
        title: Text(t['title'].toString(),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${nameOf[t['assigned_to']] ?? 'Unassigned'}'
                  '${t['due_date'] != null ? '  •  Due ${t['due_date']}' : ''}'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                StatusChip(t['status'] as String),
                StatusChip(t['priority'] as String),
              ]),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == '_delete') {
              _deleteTask(t);
            } else {
              _setStatus(t, v);
            }
          },
          itemBuilder: (_) => [
            for (final s in taskTransitions[t['status']] ?? <String>{})
              PopupMenuItem(value: s, child: Text('Move to ${pretty(s)}')),
            const PopupMenuItem(value: '_delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
