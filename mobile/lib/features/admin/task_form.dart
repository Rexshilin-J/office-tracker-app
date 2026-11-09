import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';

/// Employees who can be assigned in [project]: its team + manager.
/// With no project given, everyone is offered.
List<Opt> assigneeOpts(
  Map<String, dynamic>? project,
  List<Map<String, dynamic>> employees,
) {
  final all = employeeOpts(employees);
  if (project == null) return all;
  final ids = <dynamic>{
    ...(project['team_members'] as List),
    if (project['project_manager'] != null) project['project_manager'],
  };
  return all.where((o) => ids.contains(o.value)).toList();
}

/// Add / edit task. [projectId] fixes the project (used inside a project screen).
/// Returns true when saved.
Future<bool> showTaskForm(
  BuildContext context, {
  Map<String, dynamic>? task,
  required List<Map<String, dynamic>> projects,
  required List<Map<String, dynamic>> employees,
  int? projectId,
}) {
  final t = task;
  final fixedId = t != null ? t['project'] : projectId;

  Map<String, dynamic>? project;
  for (final p in projects) {
    if (p['id'] == fixedId) project = p;
  }

  final opts = assigneeOpts(project, employees);
  final dynamic currentAssignee = t == null ? null : t['assigned_to'];
  final dynamic assignee =
      opts.any((o) => o.value == currentAssignee) ? currentAssignee : null;

  return showSubmitForm(
    context,
    title: t == null ? 'New task' : 'Edit task',
    fields: [
      if (fixedId == null)
        FDef('project', 'Project',
            type: FType.select,
            required: true,
            options: [
              for (final p in projects) Opt(p['id'], p['name'].toString())
            ]),
      FDef('title', 'Title', required: true, initial: t?['title']),
      FDef('description', 'Description',
          type: FType.multiline, initial: t?['description']),
      FDef('assigned_to',
          project == null ? 'Assign to' : 'Assign to (project team)',
          type: FType.select, options: opts, initial: assignee),
      FDef('priority', 'Priority',
          type: FType.select,
          required: true,
          options: priorityOpts,
          initial: t?['priority'] ?? 'MEDIUM'),
      FDef('due_date', 'Due date', type: FType.date, initial: t?['due_date']),
    ],
    submit: (values) {
      final body = cleanPayload(
        values,
        nullable: {'assigned_to', 'due_date'},
        text: {'description'},
      );
      if (t == null && fixedId != null) body['project'] = fixedId;
      return t == null
          ? Api.instance.post('/api/tasks/', body)
          : Api.instance.patch('/api/tasks/${t['id']}/', body);
    },
  );
}
