import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';
import 'attendance_manage.dart';

class PeopleTab extends StatelessWidget {
  final Session session;
  const PeopleTab({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, Widget)>[
      ('Employees', _EmployeesList(session: session)),
      if (session.can('manage_clients')) ('Clients', const _ClientsList()),
      if (session.can('manage_attendance'))
        ('Attendance',
            AttendanceManageView(showTimeEntries: session.isSuperAdmin)),
    ];

    if (tabs.length == 1) return tabs.first.$2;

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          TabBar(tabs: [for (final t in tabs) Tab(text: t.$1)]),
          Expanded(child: TabBarView(children: [for (final t in tabs) t.$2])),
        ],
      ),
    );
  }
}

const List<Opt> roleOpts = [
  Opt('EMPLOYEE', 'Employee'),
  Opt('MANAGER', 'Manager'),
  Opt('HR', 'HR'),
  Opt('SUPER_ADMIN', 'Super Admin'),
];

// ------------------------------------------------------------- employees

class _EmployeesList extends StatefulWidget {
  final Session session;
  const _EmployeesList({required this.session});

  @override
  State<_EmployeesList> createState() => _EmployeesListState();
}

class _EmployeesListState extends State<_EmployeesList>
    with LivePolling<_EmployeesList>, AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> employees = [];
  String? error;
  bool loaded = false;

  @override
  bool get wantKeepAlive => true;

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
      final data = await Api.instance.get('/api/auth/employees/');
      if (!mounted) return;
      setState(() {
        employees = asMapList(data);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _add() async {
    final saved = await showSubmitForm(
      context,
      title: 'New account',
      fields: const [
        FDef('username', 'Username', required: true),
        FDef('email', 'Email', type: FType.email, required: true),
        FDef('password', 'Password (min 8)',
            type: FType.password, required: true),
        FDef('employee_id', 'Employee ID', required: true),
        FDef('phone', 'Phone'),
        FDef('role', 'Role',
            type: FType.select,
            required: true,
            initial: 'EMPLOYEE',
            options: roleOpts),
        FDef('department', 'Department'),
        FDef('designation', 'Designation'),
        FDef('work_mode', 'Work mode',
            type: FType.select,
            required: true,
            initial: 'HYBRID',
            options: [
              Opt('OFFICE', 'Office'),
              Opt('REMOTE', 'Remote'),
              Opt('HYBRID', 'Hybrid'),
            ]),
      ],
      submit: (values) =>
          Api.instance.post('/api/auth/register/', cleanPayload(values)),
    );
    if (saved) {
      if (mounted) snack(context, 'Account created.', error: false);
      refresh();
    }
  }

  Future<void> _edit(Map<String, dynamic> e) async {
    final saved = await showSubmitForm(
      context,
      title: 'Edit ${e['username']}',
      fields: [
        FDef('email', 'Email',
            type: FType.email, required: true, initial: e['email']),
        FDef('employee_id', 'Employee ID',
            required: true, initial: e['employee_id']),
        FDef('phone', 'Phone', initial: e['phone']),
        if (widget.session.can('manage_accounts'))
          FDef('role', 'Role',
              type: FType.select,
              required: true,
              initial: e['role'],
              options: roleOpts),
        FDef('department', 'Department', initial: e['department']),
        FDef('designation', 'Designation', initial: e['designation']),
        FDef('work_mode', 'Work mode',
            type: FType.select,
            required: true,
            initial: (e['work_mode'] ?? '').toString().isEmpty
                ? 'HYBRID'
                : e['work_mode'],
            options: const [
              Opt('OFFICE', 'Office'),
              Opt('REMOTE', 'Remote'),
              Opt('HYBRID', 'Hybrid'),
            ]),
      ],
      submit: (values) => Api.instance.patch(
        '/api/auth/employees/${e['id']}/',
        cleanPayload(values, text: {'phone', 'department', 'designation'}),
      ),
    );
    if (saved) refresh();
  }

  Future<void> _resetPassword(Map<String, dynamic> e) async {
    final values = await showFormDialog(
      context,
      title: 'Reset password: ${e['username']}',
      fields: const [
        FDef('password', 'New password (min 8)',
            type: FType.password, required: true),
      ],
    );
    if (values == null || !mounted) return;
    final ok = await guarded(
      context,
      () => Api.instance.patch(
          '/api/auth/employees/${e['id']}/', {'password': values['password']}),
    );
    if (ok && mounted) snack(context, 'Password maathiyaachu.', error: false);
  }

  Future<void> _toggleActive(Map<String, dynamic> e) async {
    final active = e['is_active'] != false;
    if (active &&
        !await confirm(context, 'Deactivate',
            '${e['username']} login panna mudiyaadhu. Data appadiye irukkum. Continue?')) {
      return;
    }
    if (!mounted) return;
    if (await guarded(context,
        () => Api.instance.patch('/api/auth/employees/${e['id']}/', {'is_active': !active}))) {
      refresh();
    }
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await confirm(
      context,
      'Delete employee',
      '${e['username']} permanent-a delete aagum. Avanga attendance and time log-um poidum. '
          'Tasks "Unassigned" aagum. (Login block mattum venumna Deactivate use pannunga.)',
    );
    if (!ok || !mounted) return;
    if (await guarded(context, () => Api.instance.delete('/api/auth/employees/${e['id']}/'))) {
      refresh();
    }
  }

  /// Super Admin edits anyone; HR only plain employees; others nobody.
  bool _canEdit(Map<String, dynamic> e) {
    final s = widget.session;
    if (s.can('manage_accounts')) return true;
    return s.can('manage_employees') && e['role'] == 'EMPLOYEE';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      floatingActionButton: widget.session.can('manage_accounts')
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add),
              label: const Text('Account'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            if (error != null) ErrorBanner(error!),
            for (final e in employees)
              Card(
                child: ListTile(
                  onTap: _canEdit(e) ? () => _edit(e) : null,
                  leading: CircleAvatar(
                    backgroundColor:
                        e['is_active'] == false ? Colors.grey.shade300 : null,
                    child: Text(e['username'].toString().substring(0, 1).toUpperCase()),
                  ),
                  title: Text('${e['username']}'
                      '${e['employee_id'].toString().isEmpty ? '' : '  (${e['employee_id']})'}'),
                  subtitle: Text([
                    if (e['is_active'] == false) 'INACTIVE',
                    e['designation'],
                    e['department'],
                    e['work_mode'],
                  ].where((x) => x != null && x.toString().isNotEmpty).join('  •  ')),
                  trailing: !_canEdit(e)
                      ? Chip(label: Text(pretty(e['role'].toString())))
                      : PopupMenuButton<String>(
                          onSelected: (v) {
                            switch (v) {
                              case 'edit':
                                _edit(e);
                              case 'password':
                                _resetPassword(e);
                              case 'toggle':
                                _toggleActive(e);
                              case 'delete':
                                _delete(e);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                                enabled: false,
                                child: Text(pretty(e['role'].toString()))),
                            const PopupMenuItem(
                                value: 'edit', child: Text('Edit')),
                            const PopupMenuItem(
                                value: 'password',
                                child: Text('Reset password')),
                            PopupMenuItem(
                                value: 'toggle',
                                child: Text(e['is_active'] == false
                                    ? 'Activate'
                                    : 'Deactivate')),
                            if (widget.session.can('manage_accounts'))
                              const PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- clients

class _ClientsList extends StatefulWidget {
  const _ClientsList();

  @override
  State<_ClientsList> createState() => _ClientsListState();
}

class _ClientsListState extends State<_ClientsList>
    with LivePolling<_ClientsList>, AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> clients = [];
  String? error;
  bool loaded = false;

  @override
  bool get wantKeepAlive => true;

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
      final data = await Api.instance.get('/api/clients/');
      if (!mounted) return;
      setState(() {
        clients = asMapList(data);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? c]) async {
    final saved = await showSubmitForm(
      context,
      title: c == null ? 'New client' : 'Edit client',
      fields: [
        FDef('company_name', 'Company name',
            required: true, initial: c?['company_name']),
        FDef('contact_person', 'Contact person', initial: c?['contact_person']),
        FDef('email', 'Email', type: FType.email, initial: c?['email']),
        FDef('phone', 'Phone', initial: c?['phone']),
        FDef('website', 'Website (https://...)', initial: c?['website']),
        FDef('address', 'Address', type: FType.multiline, initial: c?['address']),
        FDef('notes', 'Notes', type: FType.multiline, initial: c?['notes']),
      ],
      submit: (values) {
        final body = cleanPayload(
          values,
          text: {'contact_person', 'email', 'phone', 'website', 'address', 'notes'},
        );
        return c == null
            ? Api.instance.post('/api/clients/', body)
            : Api.instance.patch('/api/clients/${c['id']}/', body);
      },
    );
    if (saved) refresh();
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    if (!await confirm(context, 'Delete client',
        '"${c['company_name']}" delete pannanuma? Projects delete aagaadhu, client link mattum remove aagum.')) {
      return;
    }
    if (!mounted) return;
    if (await guarded(context, () => Api.instance.delete('/api/clients/${c['id']}/'))) {
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_business),
        label: const Text('Client'),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            if (error != null) ErrorBanner(error!),
            if (clients.isEmpty) const EmptyState('Clients illa.'),
            for (final c in clients)
              Card(
                child: ListTile(
                  onTap: () => _openForm(c),
                  leading: const CircleAvatar(child: Icon(Icons.business)),
                  title: Text(c['company_name'].toString()),
                  subtitle: Text([c['contact_person'], c['phone'], c['email']]
                      .where((x) => x != null && x.toString().isNotEmpty)
                      .join('  •  ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(c),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
