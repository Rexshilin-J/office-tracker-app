import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';

/// Admin: view, add, edit and delete attendance + time entries for any day.
class AttendanceManageView extends StatefulWidget {
  /// Time entries (and deleting them) are for the Super Admin only.
  final bool showTimeEntries;
  const AttendanceManageView({super.key, this.showTimeEntries = true});

  @override
  State<AttendanceManageView> createState() => _AttendanceManageViewState();
}

class _AttendanceManageViewState extends State<AttendanceManageView>
    with LivePolling<AttendanceManageView>, AutomaticKeepAliveClientMixin {
  DateTime day = DateTime.now();
  List<Map<String, dynamic>> records = [];
  List<Map<String, dynamic>> entries = [];
  List<Map<String, dynamic>> employees = [];
  String? error;
  bool loaded = false;

  String get dayStr => day.toIso8601String().substring(0, 10);

  @override
  bool get wantKeepAlive => true;

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
        Api.instance.get('/api/attendance/manage/', query: {'date': dayStr}),
        if (widget.showTimeEntries)
          Api.instance.get('/api/time-tracking/',
              query: {'date_from': dayStr, 'date_to': dayStr})
        else
          Future<dynamic>.value(<dynamic>[]),
        Api.instance.get('/api/auth/employees/'),
      ]);
      if (!mounted) return;
      setState(() {
        records = asMapList(r[0]);
        entries = asMapList(r[1]);
        employees = asMapList(r[2]);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  void _moveDay(int delta) {
    setState(() => day = day.add(Duration(days: delta)));
    refresh();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => day = picked);
      refresh();
    }
  }

  Future<void> _openForm([Map<String, dynamic>? r]) async {
    final values = await showFormDialog(
      context,
      title: r == null ? 'Add attendance ($dayStr)' : 'Edit ${r['username']}',
      fields: [
        if (r == null)
          FDef('user', 'Employee',
              type: FType.select,
              required: true,
              options: employeeOpts(employees)),
        FDef('check_in', 'Check-in time',
            type: FType.time, required: false, initial: hhmmOf(r?['check_in'])),
        FDef('check_out', 'Check-out time',
            type: FType.time, initial: hhmmOf(r?['check_out'])),
        FDef('status', 'Status',
            type: FType.select,
            required: true,
            initial: r?['status'] ?? 'PRESENT',
            options: const [
              Opt('PRESENT', 'Present'),
              Opt('HALF_DAY', 'Half day'),
              Opt('ABSENT', 'Absent'),
            ]),
      ],
    );
    if (values == null || !mounted) return;

    final body = <String, dynamic>{
      'check_in': localIso(r?['date']?.toString() ?? dayStr, values['check_in']),
      'check_out': localIso(r?['date']?.toString() ?? dayStr, values['check_out']),
      'status': values['status'],
    };
    if (r == null) {
      body['user'] = values['user'];
      body['date'] = dayStr;
    }

    final ok = await guarded(
      context,
      () => r == null
          ? Api.instance.post('/api/attendance/manage/', body)
          : Api.instance.patch('/api/attendance/manage/${r['id']}/', body),
    );
    if (ok) refresh();
  }

  Future<void> _deleteRecord(Map<String, dynamic> r) async {
    if (!await confirm(context, 'Delete attendance',
        '${r['username']} - ${r['date']} record delete pannanuma?')) {
      return;
    }
    if (!mounted) return;
    if (await guarded(
        context, () => Api.instance.delete('/api/attendance/manage/${r['id']}/'))) {
      refresh();
    }
  }

  Future<void> _deleteEntry(Map<String, dynamic> e) async {
    if (!await confirm(context, 'Delete time entry',
        '${e['username']} - ${e['task_title']} entry delete pannanuma?')) {
      return;
    }
    if (!mounted) return;
    if (await guarded(
        context, () => Api.instance.delete('/api/time-tracking/${e['id']}/'))) {
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fetched = DateTime.now();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Attendance'),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _moveDay(-1)),
              TextButton.icon(
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(dayStr),
              ),
              IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _moveDay(1)),
            ],
          ),
          Expanded(
            child: !loaded && error == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                      children: [
                        if (error != null) ErrorBanner(error!),
                        Text('Attendance (${records.length})',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (records.isEmpty)
                          const EmptyState('Intha naal attendance illa.'),
                        for (final r in records)
                          Card(
                            child: ListTile(
                              onTap: () => _openForm(r),
                              title: Text(r['username'].toString()),
                              subtitle: Text(
                                  'In ${fmtTime(r['check_in'])}   Out ${fmtTime(r['check_out'])}'
                                  '   •   ${fmtHm((r['worked_seconds'] ?? 0) as int)}'),
                              leading: StatusChip(r['status'].toString()),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteRecord(r),
                              ),
                            ),
                          ),
                        if (widget.showTimeEntries) ...[
                        const SizedBox(height: 20),
                        Text('Time entries (${entries.length})',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (entries.isEmpty)
                          const EmptyState('Intha naal time entries illa.'),
                        for (final e in entries)
                          Card(
                            child: ListTile(
                              title: Text('${e['username']}  •  ${e['task_title']}'),
                              subtitle: Text(
                                  '${fmtTime(e['started_at'])} - ${e['ended_at'] == null ? 'running' : fmtTime(e['ended_at'])}'),
                              leading: StatusChip(e['status'].toString()),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  e['status'] == 'STOPPED'
                                      ? Text(fmtHm((e['duration_seconds'] ?? 0) as int))
                                      : LiveDuration(
                                          baseSeconds:
                                              (e['elapsed_seconds'] ?? 0) as int,
                                          running: e['status'] == 'RUNNING',
                                          fetchedAt: fetched,
                                        ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _deleteEntry(e),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
