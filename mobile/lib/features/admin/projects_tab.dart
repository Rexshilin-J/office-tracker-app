import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';
import 'project_detail.dart';
import 'project_form.dart';

class ProjectsTab extends StatefulWidget {
  const ProjectsTab({super.key});

  @override
  State<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<ProjectsTab>
    with LivePolling<ProjectsTab> {
  List<Map<String, dynamic>> projects = [];
  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> employees = [];
  String filter = 'ALL';
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
      final r = await Future.wait<dynamic>([
        Api.instance.get('/api/projects/'),
        Api.instance.get('/api/clients/'),
        Api.instance.get('/api/auth/employees/'),
      ]);
      if (!mounted) return;
      setState(() {
        projects = asMapList(r[0]);
        clients = asMapList(r[1]);
        employees = asMapList(r[2]);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _form([Map<String, dynamic>? p]) async {
    final saved = await showProjectForm(
      context,
      project: p,
      clients: clients,
      employees: employees,
    );
    if (saved) refresh();
  }

  Future<void> _open(Map<String, dynamic> p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(
          projectId: p['id'] as int,
          clients: clients,
          employees: employees,
        ),
      ),
    );
    if (mounted) refresh();
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    if (!await confirm(context, 'Delete project',
        '"${p['name']}" and its ${p['total_tasks']} tasks (time entries-um) delete aagum. Sure-a?')) {
      return;
    }
    if (!mounted) return;
    if (await guarded(
        context, () => Api.instance.delete('/api/projects/${p['id']}/'))) {
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final shown = filter == 'ALL'
        ? projects
        : projects.where((p) => p['status'] == filter).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _form(),
        icon: const Icon(Icons.add),
        label: const Text('Project'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (final s in [
                  'ALL',
                  'PLANNING',
                  'IN_PROGRESS',
                  'ON_HOLD',
                  'COMPLETED',
                  'CANCELLED'
                ])
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
                  if (shown.isEmpty)
                    const EmptyState('Projects illa. + click pannunga.'),
                  for (final p in shown) _card(p),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final overdue = p['is_overdue'] == true;
    final members = (p['team_members'] as List).length;
    final progress = ((p['progress_percent'] ?? 0) as int) / 100;

    final accent = overdue
        ? Colors.red
        : statusColor(p['status'] as String);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(p),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 6)),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [accent.withValues(alpha: 0.07), Colors.white],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(p['name'].toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _form(p);
                      if (v == 'delete') _delete(p);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              Text(
                '${p['client_name'] ?? 'No client'}  •  $members members',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
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
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: LinearProgressIndicator(
                  value: progress,
                  color: accent,
                  backgroundColor: accent.withValues(alpha: 0.15),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${p['completed_tasks']}/${p['total_tasks']} tasks  •  ${p['progress_percent']}%'
                '${p['deadline'] != null ? '  •  Due ${p['deadline']}' : ''}',
                style: TextStyle(
                  fontSize: 13,
                  color: overdue ? Colors.red : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
