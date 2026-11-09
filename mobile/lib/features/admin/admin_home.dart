import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../shared/ui.dart';
import '../employee/employee_home.dart';
import 'dashboard_tab.dart';
import 'expenses_tab.dart';
import 'people_tab.dart';
import 'projects_tab.dart';
import 'reports_tab.dart';
import 'tasks_tab.dart';

class _TabDef {
  final String label;
  final IconData icon;
  final Color color;
  final Widget Function() build;
  const _TabDef(this.label, this.icon, this.color, this.build);
}

/// Management app for Super Admin, HR and Manager.
/// Which tabs (and which buttons inside them) show up depends on
/// `session.can(...)`, i.e. on what the server allows that role to do.
class AdminHome extends StatefulWidget {
  final Session session;
  const AdminHome({super.key, required this.session});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _index = 0;

  List<_TabDef> _tabs() {
    final s = widget.session;
    return [
      if (s.can('view_dashboard'))
        _TabDef('Dashboard', Icons.dashboard_rounded, const Color(0xFF4F46E5), () => const DashboardTab()),
      if (s.can('manage_work')) ...[
        _TabDef('Projects', Icons.folder_rounded, const Color(0xFF2563EB), () => const ProjectsTab()),
        _TabDef('Tasks', Icons.task_alt_rounded, const Color(0xFF0D9488), () => const TasksTab()),
      ],
      if (s.can('manage_expenses'))
        _TabDef('Expenses', Icons.receipt_long_rounded,
            const Color(0xFFF97316), () => const ExpensesTab()),
      if (s.can('view_employees'))
        _TabDef(s.can('manage_accounts') || s.can('manage_employees') ? 'People' : 'Team',
            Icons.people_alt_rounded, const Color(0xFFDB2777),
            () => PeopleTab(session: s)),
      if (s.can('view_attendance_report') || s.can('view_work_reports'))
        _TabDef('Reports', Icons.bar_chart_rounded, const Color(0xFF7C3AED), () => ReportsTab(session: s)),
      // HR and managers also work: attendance, timer and their own tasks.
      if (!s.isSuperAdmin)
        _TabDef('My Day', Icons.today_rounded, const Color(0xFF16A34A), () => const MyDayView()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    if (_index >= tabs.length) _index = 0;

    return Scaffold(
      appBar: gradientAppBar(
        color: tabs[_index].color,
        title: Text(tabs[_index].label),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '${widget.session.username} • ${widget.session.roleLabel}',
                style: const TextStyle(fontSize: 13, color: Colors.white),
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
      // Only the visible tab polls the server; others load when opened.
      body: KeyedSubtree(
        key: ValueKey(tabs[_index].label),
        child: tabs[_index].build(),
      ),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: _index,
              labelBehavior: tabs.length > 5
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (i) => setState(() => _index = i),
              indicatorColor: tabs[_index].color.withValues(alpha: 0.16),
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
