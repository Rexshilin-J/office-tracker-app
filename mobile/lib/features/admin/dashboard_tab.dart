import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab>
    with LivePolling<DashboardTab> {
  Map<String, dynamic> data = {};
  List<Map<String, dynamic>> timers = [];
  List<Map<String, dynamic>> present = [];
  DateTime fetchedAt = DateTime.now();
  String? error;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> refresh() async {
    try {
      final r = asMap(await Api.instance.get('/api/reports/dashboard/'));
      if (!mounted) return;
      setState(() {
        data = r;
        timers = asMapList(r['active_timer_list']);
        present = asMapList(r['attendance_today']);
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

    final emp = asMap(data['employees']);
    final tasks = asMap(data['tasks']);
    final proj = asMap(data['projects']);
    final width = MediaQuery.of(context).size.width;
    final cols = width > 900 ? 4 : (width > 600 ? 3 : 2);

    final cards = <Widget>[
      StatCard(
          label: 'Checked in today',
          value: '${emp['checked_in_today'] ?? 0}/${emp['total'] ?? 0}',
          icon: Icons.login,
          color: Colors.green),
      StatCard(
          label: 'Still working',
          value: '${emp['still_working'] ?? 0}',
          icon: Icons.work,
          color: Colors.blue),
      StatCard(
          label: 'Not checked in',
          value: '${emp['not_checked_in'] ?? 0}',
          icon: Icons.person_off,
          color: Colors.grey),
      StatCard(
          label: 'Active timers',
          value: '${data['active_timers'] ?? 0}',
          icon: Icons.timer,
          color: Colors.indigo),
      StatCard(
          label: 'Tracked today',
          value: fmtHm((data['tracked_seconds_today'] ?? 0) as int),
          icon: Icons.hourglass_bottom,
          color: Colors.teal),
      StatCard(
          label: 'Overdue tasks',
          value: '${tasks['overdue'] ?? 0}',
          icon: Icons.warning_amber,
          color: Colors.red),
    ];

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null) ErrorBanner(error!),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('Live  •  auto-refresh every 8s',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: cols == 2 ? 1.25 : 1.5,
            children: cards,
          ),
          const SizedBox(height: 20),
          Text('Tasks', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in ['todo', 'in_progress', 'in_review', 'completed'])
                _tint(statusColor(s.toUpperCase()),
                    '${pretty(s)}: ${tasks[s] ?? 0}'),
              _tint(const Color(0xFF7C3AED),
                  'Projects: ${proj['in_progress'] ?? 0} active / ${proj['total'] ?? 0}'),
            ],
          ),
          const SizedBox(height: 20),
          Text("Today's attendance",
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (present.isEmpty) const EmptyState('Innaikku yaarum check in pannala.'),
          for (final a in present)
            Card(
              child: ListTile(
                dense: true,
                leading: Icon(
                  a['check_out'] == null ? Icons.circle : Icons.check_circle,
                  size: 16,
                  color: a['check_out'] == null ? Colors.green : Colors.grey,
                ),
                title: Text(a['username'].toString()),
                subtitle: Text(
                    'In ${fmtTime(a['check_in'])}   Out ${fmtTime(a['check_out'])}'),
                trailing: Text(a['check_out'] == null ? 'Working' : 'Left',
                    style: TextStyle(
                        color: a['check_out'] == null
                            ? Colors.green
                            : Colors.grey)),
              ),
            ),
          const SizedBox(height: 20),
          Text("Who's working now",
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (timers.isEmpty) const EmptyState('Ippo yaarum timer run pannala.'),
          for (final t in timers)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    (t['username'] ?? '?').toString().substring(0, 1).toUpperCase(),
                  ),
                ),
                title: Text('${t['username']}  •  ${t['task_title']}'),
                subtitle: StatusChip(t['status'] as String),
                trailing: LiveDuration(
                  baseSeconds: (t['elapsed_seconds'] ?? 0) as int,
                  running: t['status'] == 'RUNNING',
                  fetchedAt: fetchedAt,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tint(Color c, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Text(text,
            style: TextStyle(
                color: c, fontWeight: FontWeight.w600, fontSize: 13)),
      );
}
