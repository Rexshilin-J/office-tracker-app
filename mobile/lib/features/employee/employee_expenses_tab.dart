import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';
// Reuse the Admin screen's category list, payment options and money format.
import '../admin/expenses_tab.dart'
    show ExpCat, catOf, expenseCats, fmtMoney, paymentOpts;
import 'employee_attendance_tab.dart' show StatSquare;
import 'employee_widgets.dart';

Color claimColor(String status) {
  switch (status) {
    case 'APPROVED':
      return Colors.green;
    case 'REJECTED':
      return Colors.red;
    default:
      return Colors.orange;
  }
}

/// "My Expenses": claim an expense and follow its approval status.
class MyExpensesTab extends StatefulWidget {
  const MyExpensesTab({super.key});

  @override
  State<MyExpensesTab> createState() => _MyExpensesTabState();
}

class _MyExpensesTabState extends State<MyExpensesTab>
    with LivePolling<MyExpensesTab> {
  /// Categories an employee can claim (a subset of the company categories).
  static const List<String> _claimable = [
    'TRAVEL',
    'FOOD',
    'SUPPLIES',
    'SOFTWARE',
    'MAINTENANCE',
    'OTHER',
  ];
  static const List<String> _filters = ['ALL', 'PENDING', 'APPROVED', 'REJECTED'];

  List<Map<String, dynamic>> claims = [];
  String filter = 'ALL';
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
      final data = await Api.instance.get('/api/expenses/claims/');
      if (!mounted) return;
      setState(() {
        claims = asMapList(data);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  double _sum(String status) => claims
      .where((c) => c['status'] == status)
      .fold<double>(0, (s, c) => s + asDouble(c['amount']));

  Future<void> _add() async {
    // Optional project list for the form (only projects I belong to).
    var projects = <Map<String, dynamic>>[];
    try {
      projects = asMapList(await Api.instance.get('/api/projects/'));
    } on ApiException catch (_) {}
    if (!mounted) return;

    final ok = await showSubmitForm(
      context,
      title: 'New expense claim',
      fields: [
        const FDef('title', 'What was it for?', required: true),
        const FDef('amount', 'Amount (₹)', required: true),
        FDef(
          'category',
          'Category',
          type: FType.select,
          required: true,
          initial: 'TRAVEL',
          options: [
            for (final c in expenseCats.where((c) => _claimable.contains(c.key)))
              Opt(c.key, c.label),
          ],
        ),
        FDef(
          'payment_method',
          'Paid via',
          type: FType.select,
          required: true,
          initial: 'CASH',
          options: paymentOpts,
        ),
        FDef('date', 'Expense date', type: FType.date, initial: todayStr()),
        FDef(
          'project',
          'Project (optional)',
          type: FType.select,
          options: [
            for (final p in projects) Opt(p['id'], asText(p['name'])),
          ],
        ),
        const FDef('notes', 'Notes (optional)', type: FType.multiline),
      ],
      submit: (values) => Api.instance.post(
        '/api/expenses/claims/',
        cleanPayload(values, text: {'notes'}),
      ),
    );

    if (ok && mounted) {
      snack(context, 'Claim submitted for approval.', error: false);
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final shown =
        filter == 'ALL' ? claims : claims.where((c) => c['status'] == filter).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Claim'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f == 'ALL' ? 'All' : pretty(f)),
                      selected: filter == f,
                      onSelected: (_) => setState(() => filter = f),
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
                  Row(
                    children: [
                      Expanded(
                        child: StatSquare(
                          label: 'Pending',
                          value: fmtMoney(_sum('PENDING')),
                          icon: Icons.hourglass_top,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatSquare(
                          label: 'Approved',
                          value: fmtMoney(_sum('APPROVED')),
                          icon: Icons.check_circle,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatSquare(
                          label: 'Rejected',
                          value: fmtMoney(_sum('REJECTED')),
                          icon: Icons.cancel,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SectionHeader('Expense history'),
                  if (shown.isEmpty)
                    EmptyState(
                      filter == 'ALL'
                          ? 'No claims yet. Tap + Claim to add one.'
                          : 'No ${pretty(filter).toLowerCase()} claims.',
                    ),
                  for (final c in shown) _card(c),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> c) {
    final status = asText(c['status'], 'PENDING');
    final color = claimColor(status);
    final ExpCat cat = catOf(asText(c['category'], 'OTHER'));
    final notes = asText(c['notes']);
    final reviewNote = asText(c['review_note']);
    final project = asText(c['project_name']);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 6)),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [color.withValues(alpha: 0.06), Colors.white],
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: cat.color.withValues(alpha: 0.15),
                  child: Icon(cat.icon, size: 18, color: cat.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asText(c['title']),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '${cat.label}  •  ${fmtDay(c['date'])}'
                        '${project.isEmpty ? '' : '  •  $project'}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Text(
                  fmtMoney(asDouble(c['amount'])),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    pretty(status),
                    style: TextStyle(
                        color: color, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Text(
                  'Submitted ${fmtIsoDay(c['created_at'])}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(notes, style: TextStyle(color: Colors.grey.shade800)),
            ],
            if (reviewNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${status == 'REJECTED' ? 'Reason' : 'Reviewer note'}: $reviewNote',
                  style: TextStyle(color: color.withValues(alpha: 1), fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
