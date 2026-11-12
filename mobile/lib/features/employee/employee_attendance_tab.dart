import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';
import 'employee_widgets.dart';

/// "Attendance": the employee's own day-by-day history.
class MyAttendanceTab extends StatefulWidget {
  const MyAttendanceTab({super.key});

  @override
  State<MyAttendanceTab> createState() => _MyAttendanceTabState();
}

class _MyAttendanceTabState extends State<MyAttendanceTab>
    with LivePolling<MyAttendanceTab> {
  static const Color _color = Color(0xFF16A34A);
  static const List<int> _ranges = [7, 30, 90];

  List<Map<String, dynamic>> records = [];
  DateTime fetchedAt = DateTime.now();
  int days = 30;
  String? error;
  bool loaded = false;

  @override
  Duration get pollInterval => const Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  Future<void> refresh() async {
    try {
      final data = await Api.instance.get(
        '/api/attendance/history/',
        query: {'date_from': daysAgoStr(days - 1), 'date_to': todayStr()},
      );
      if (!mounted) return;
      setState(() {
        records = asMapList(data);
        fetchedAt = DateTime.now();
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  /// Worked seconds for a row. For a day still in progress, counts up to now.
  int _worked(Map<String, dynamic> r) {
    if (r['check_out'] != null) return asInt(r['worked_seconds']);
    final ci = DateTime.tryParse(asText(r['check_in']));
    if (ci == null) return 0;
    final s = DateTime.now().difference(ci).inSeconds;
    return s < 0 ? 0 : s;
  }

  bool _inProgress(Map<String, dynamic> r) =>
      r['check_in'] != null && r['check_out'] == null;

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final worked = records.where((r) => r['check_in'] != null).toList();
    final totalSeconds = worked.fold<int>(0, (sum, r) => sum + _worked(r));
    final avg = worked.isEmpty ? 0 : totalSeconds ~/ worked.length;
    final present = records
        .where((r) => r['status'] == 'PRESENT' || r['status'] == 'HALF_DAY')
        .length;

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final d in _ranges)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('Last $d days'),
                    selected: days == d,
                    onSelected: (_) {
                      setState(() {
                        days = d;
                        loaded = false;
                      });
                      refresh();
                    },
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
                Row(
                  children: [
                    Expanded(
                      child: StatSquare(
                        label: 'Days present',
                        value: '$present',
                        icon: Icons.event_available,
                        color: _color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatSquare(
                        label: 'Total hours',
                        value: fmtHm(totalSeconds),
                        icon: Icons.hourglass_bottom,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatSquare(
                        label: 'Daily average',
                        value: fmtHm(avg),
                        icon: Icons.av_timer,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
                const SectionHeader('Daily attendance'),
                if (records.isEmpty)
                  const EmptyState('No attendance records in this period.'),
                for (final r in records) _row(r),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final status = asText(r['status'], 'PRESENT');
    final inProgress = _inProgress(r);
    final color = inProgress
        ? Colors.green
        : (status == 'ABSENT'
            ? Colors.red
            : (status == 'HALF_DAY' ? Colors.orange : Colors.indigo));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    asText(r['date']).length >= 10 ? asText(r['date']).substring(8, 10) : '--',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: color),
                  ),
                  Text(
                    fmtWeekday(r['date']),
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmtDay(r['date']),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'In ${fmtTime(r['check_in'])}   Out ${inProgress ? 'working' : fmtTime(r['check_out'])}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  r['check_in'] == null ? '--' : fmtHm(_worked(r)),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  inProgress ? 'In progress' : pretty(status),
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small coloured tile for three-across summaries.
class StatSquare extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const StatSquare({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: colorGradient(color),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
