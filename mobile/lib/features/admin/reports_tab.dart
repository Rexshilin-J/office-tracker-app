import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';

class ReportsTab extends StatefulWidget {
  final Session session;
  const ReportsTab({super.key, required this.session});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> with LivePolling<ReportsTab> {
  int days = 7;
  Map<String, dynamic> workTime = {};
  Map<String, dynamic> attendance = {};
  Map<String, dynamic> projects = {};
  Map<String, dynamic> tasks = {};
  String? error;
  bool loaded = false;

  bool get showWork => widget.session.can('view_work_reports');
  bool get showAttendance => widget.session.can('view_attendance_report');

  @override
  Duration get pollInterval => const Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> refresh() async {
    final range = {'date_from': daysAgoStr(days - 1), 'date_to': todayStr()};
    try {
      Future<dynamic> none() => Future<dynamic>.value(<String, dynamic>{});
      final r = await Future.wait<dynamic>([
        showWork
            ? Api.instance.get('/api/reports/work-time/', query: range)
            : none(),
        showAttendance
            ? Api.instance.get('/api/reports/attendance/', query: range)
            : none(),
        showWork
            ? Api.instance.get('/api/reports/projects/', query: range)
            : none(),
        showWork ? Api.instance.get('/api/reports/tasks/') : none(),
      ]);
      if (!mounted) return;
      setState(() {
        workTime = asMap(r[0]);
        attendance = asMap(r[1]);
        projects = asMap(r[2]);
        tasks = asMap(r[3]);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Widget _section(String title, List<Widget> children, {String? empty}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (children.isEmpty) EmptyState(empty ?? 'No data'),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final perUser = asMapList(workTime['per_user']);
    final perTask = asMapList(workTime['per_task']);
    final att = asMapList(attendance['results']);
    final proj = asMapList(projects['results']);
    final perEmp = asMapList(tasks['per_employee']);

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null) ErrorBanner(error!),
          Wrap(
            spacing: 8,
            children: [
              for (final d in [7, 30])
                ChoiceChip(
                  label: Text('Last $d days'),
                  selected: days == d,
                  onSelected: (_) {
                    setState(() => days = d);
                    refresh();
                  },
                ),
            ],
          ),
          if (showWork)
          Card(
            margin: const EdgeInsets.only(top: 12),
            child: ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('Total tracked time'),
              trailing: Text(
                fmtHm((workTime['total_seconds'] ?? 0) as int),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (showWork)
          _section('Work time by employee', [
            for (final r in perUser)
              Card(
                child: ListTile(
                  title: Text(r['username'].toString()),
                  subtitle: Text('${r['sessions']} sessions'),
                  trailing: Text(fmtHm((r['total_seconds'] ?? 0) as int)),
                ),
              ),
          ], empty: 'Intha period-la time entries illa.'),
          if (showWork)
          _section('Work time by task', [
            for (final r in perTask)
              Card(
                child: ListTile(
                  title: Text(r['task'].toString()),
                  subtitle: Text(r['project'].toString()),
                  trailing: Text(fmtHm((r['total_seconds'] ?? 0) as int)),
                ),
              ),
          ]),
          if (showAttendance)
          _section('Attendance', [
            for (final r in att)
              Card(
                child: ListTile(
                  title: Text(r['username'].toString()),
                  subtitle: Text(
                      'Present ${r['days_present']}  •  Half ${r['half_days']}  •  Absent ${r['days_absent']}'
                      '${(r['missing_check_out'] ?? 0) > 0 ? '  •  No check-out ${r['missing_check_out']}' : ''}'),
                  trailing: Text(fmtHm((r['worked_seconds'] ?? 0) as int)),
                ),
              ),
          ]),
          if (showWork)
          _section('Project progress', [
            for (final r in proj)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(r['name'].toString(),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          StatusChip(r['status'] as String),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: ((r['progress_percent'] ?? 0) as int) / 100,
                      ),
                      const SizedBox(height: 6),
                      Text(
                          '${r['completed_tasks']}/${r['total_tasks']} tasks  •  ${r['progress_percent']}%  •  ${fmtHm((r['tracked_seconds'] ?? 0) as int)} tracked'),
                    ],
                  ),
                ),
              ),
          ]),
          if (showWork)
          _section('Tasks per employee', [
            for (final r in perEmp)
              Card(
                child: ListTile(
                  title: Text(r['username'].toString()),
                  subtitle: Text(
                      '${r['completed']}/${r['total']} completed  •  ${r['overdue']} overdue'),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}
