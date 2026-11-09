import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';

const List<Opt> projectStatusOpts = [
  Opt('PLANNING', 'Planning'),
  Opt('IN_PROGRESS', 'In Progress'),
  Opt('ON_HOLD', 'On Hold'),
  Opt('COMPLETED', 'Completed'),
  Opt('CANCELLED', 'Cancelled'),
];

/// Add / edit project. Stays open on server errors so nothing typed is lost.
/// Returns true when the project was saved.
Future<bool> showProjectForm(
  BuildContext context, {
  Map<String, dynamic>? project,
  required List<Map<String, dynamic>> clients,
  required List<Map<String, dynamic>> employees,
}) {
  final p = project;
  final empOpts = employeeOpts(employees);
  final validIds = empOpts.map((o) => o.value).toSet();
  final managerOpts = employeeOpts(employees, managersOnly: true);
  final managerIds = managerOpts.map((o) => o.value).toSet();
  final dynamic currentManager = p == null ? null : p['project_manager'];
  final dynamic managerInitial =
      managerIds.contains(currentManager) ? currentManager : null;

  final team = p == null
      ? <dynamic>[]
      : (p['team_members'] as List).where(validIds.contains).toList();

  return showSubmitForm(
    context,
    title: p == null ? 'New project' : 'Edit project',
    fields: [
      FDef('name', 'Project name', required: true, initial: p?['name']),
      FDef('description', 'Description',
          type: FType.multiline, initial: p?['description']),
      FDef('client', 'Client',
          type: FType.select,
          options: [
            for (final c in clients) Opt(c['id'], c['company_name'].toString())
          ],
          initial: p?['client']),
      FDef('project_manager', 'Project manager',
          type: FType.select,
          options: managerOpts,
          initial: managerInitial),
      FDef('team_members', 'Team members',
          type: FType.multi, options: empOpts, initial: team),
      FDef('start_date', 'Start date', type: FType.date, initial: p?['start_date']),
      FDef('deadline', 'Deadline', type: FType.date, initial: p?['deadline']),
      FDef('status', 'Status',
          type: FType.select,
          required: true,
          initial: p?['status'] ?? 'PLANNING',
          options: projectStatusOpts),
      FDef('priority', 'Priority',
          type: FType.select,
          required: true,
          initial: p?['priority'] ?? 'MEDIUM',
          options: priorityOpts),
    ],
    submit: (values) {
      final body = cleanPayload(
        values,
        nullable: {'client', 'project_manager', 'start_date', 'deadline'},
        text: {'description'},
      );
      return p == null
          ? Api.instance.post('/api/projects/', body)
          : Api.instance.patch('/api/projects/${p['id']}/', body);
    },
  );
}
