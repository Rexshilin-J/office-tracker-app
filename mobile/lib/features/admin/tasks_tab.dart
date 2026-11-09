import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';
import 'task_form.dart';

class TasksTab extends StatefulWidget {
  const TasksTab({super.key});

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> with LivePolling<TasksTab> {
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> projects = [];
  List<Map<String, dynamic>> employees = [];
  String filter = 'ALL';
  String? error;
  bool loaded = false;

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
        Api.instance.get('/api/projects/'),
        Api.instance.get('/api/auth/employees/'),
      ]);
      if (!mounted) return;
      setState(() {
        tasks = asMapList(r[0]);
        projects = asMapList(r[1]);
        employees = asMapList(r[2]);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? t]) async {
    if (t == null && projects.isEmpty) {
      snack(context, 'Mudhalla oru project create pannunga.');
      return;
    }
    final saved = await showTaskForm(
      context,
      task: t,
      projects: projects,
      employees: employees,
    );
    if (saved) refresh();
  }

  Future<void> _setStatus(Map<String, dynamic> t, String status) async {
    if (await guarded(context,
        () => Api.instance.patch('/api/tasks/${t['id']}/', {'status': status}))) {
      refresh();
    }
  }

  Future<void> _delete(Map<String, dynamic> t) async {
    if (!await confirm(context, 'Delete task', '"${t['title']}" delete pannanuma?')) {
      return;
    }
    if (!mounted) return;
    if (await guarded(context, () => Api.instance.delete('/api/tasks/${t['id']}/'))) {
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final shown =
        filter == 'ALL' ? tasks : tasks.where((t) => t['status'] == filter).toList();
    final nameOf = {for (final e in employees) e['id']: e['username']};

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Task'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (final s in ['ALL', 'TODO', 'IN_PROGRESS', 'IN_REVIEW', 'COMPLETED'])
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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                children: [
                  if (error != null) ErrorBanner(error!),
                  if (shown.isEmpty) const EmptyState('Tasks illa.'),
                  for (final t in shown)
                    Card(
                      child: ListTile(
                        onTap: () => _openForm(t),
                        title: Text(t['title'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${t['project_name']}  •  ${nameOf[t['assigned_to']] ?? 'Unassigned'}'
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
                              _delete(t);
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
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
