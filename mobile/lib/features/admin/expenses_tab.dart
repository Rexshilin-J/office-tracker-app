import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';

// ------------------------------------------------------------------ helpers

class ExpCat {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const ExpCat(this.key, this.label, this.icon, this.color);
}

const List<ExpCat> expenseCats = [
  ExpCat('SALARY', 'Salary', Icons.payments_rounded, Color(0xFF2E7D32)),
  ExpCat('RENT', 'Rent', Icons.home_work_rounded, Color(0xFF5E35B1)),
  ExpCat('UTILITIES', 'Utilities', Icons.bolt_rounded, Color(0xFFF9A825)),
  ExpCat('TRAVEL', 'Travel', Icons.flight_rounded, Color(0xFF0288D1)),
  ExpCat('FOOD', 'Food', Icons.restaurant_rounded, Color(0xFFEF6C00)),
  ExpCat('SUPPLIES', 'Supplies', Icons.inventory_2_rounded, Color(0xFF00897B)),
  ExpCat('SOFTWARE', 'Software', Icons.computer_rounded, Color(0xFF3949AB)),
  ExpCat('MARKETING', 'Marketing', Icons.campaign_rounded, Color(0xFFD81B60)),
  ExpCat('MAINTENANCE', 'Maintenance', Icons.build_rounded, Color(0xFF6D4C41)),
  ExpCat('OTHER', 'Other', Icons.category_rounded, Color(0xFF607D8B)),
];

ExpCat catOf(String key) =>
    expenseCats.firstWhere((c) => c.key == key, orElse: () => expenseCats.last);

const List<Opt> paymentOpts = [
  Opt('CASH', 'Cash'),
  Opt('UPI', 'UPI'),
  Opt('CARD', 'Card'),
  Opt('BANK', 'Bank Transfer'),
  Opt('CHEQUE', 'Cheque'),
];

double _num(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

/// 1234567.5 -> ₹12,34,567.50  (Indian digit grouping)
String fmtMoney(num value) {
  final neg = value < 0;
  final abs = value.abs();
  final hasFraction = (abs * 100).round() % 100 != 0;
  final parts = abs.toStringAsFixed(hasFraction ? 2 : 0).split('.');
  final digits = parts[0];
  String grouped = digits;
  if (digits.length > 3) {
    var rest = digits.substring(0, digits.length - 3);
    final last3 = digits.substring(digits.length - 3);
    final chunks = <String>[];
    while (rest.length > 2) {
      chunks.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) chunks.insert(0, rest);
    grouped = '${chunks.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String fmtCompact(num v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return v.round().toString();
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String fmtDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String _dayLabel(String iso) {
  if (iso == todayStr()) return 'Today';
  if (iso == daysAgoStr(1)) return 'Yesterday';
  return fmtDate(iso);
}

// --------------------------------------------------------------------- tab

class ExpensesTab extends StatefulWidget {
  const ExpensesTab({super.key});

  @override
  State<ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<ExpensesTab>
    with LivePolling<ExpensesTab> {
  List<Map<String, dynamic>> expenses = [];
  List<Map<String, dynamic>> projects = [];
  Map<String, dynamic> summary = {};
  String filter = 'ALL';
  bool monthOnly = true;
  String? error;
  bool loaded = false;

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
        Api.instance.get('/api/expenses/'),
        Api.instance.get('/api/expenses/summary/'),
        Api.instance.get('/api/projects/'),
      ]);
      if (!mounted) return;
      setState(() {
        expenses = asMapList(r[0]);
        summary = asMap(r[1]);
        projects = asMapList(r[2]);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _form([Map<String, dynamic>? e]) async {
    final saved = await showExpenseForm(context, expense: e, projects: projects);
    if (saved) refresh();
  }

  Future<bool> _confirmDelete(Map<String, dynamic> e) async {
    if (!await confirm(context, 'Delete expense',
        '"${e['title']}" (${fmtMoney(_num(e['amount']))}) delete pannalaama?')) {
      return false;
    }
    if (!mounted) return false;
    return guarded(context, () => Api.instance.delete('/api/expenses/${e['id']}/'));
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded && error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final shown = filter == 'ALL'
        ? expenses
        : expenses.where((e) => e['category'] == filter).toList();

    // Group by date (list is already newest first).
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in shown) {
      groups.putIfAbsent(e['date'].toString(), () => []).add(e);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _form(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Expense'),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if (error != null) ErrorBanner(error!),
            _hero(),
            const SizedBox(height: 14),
            _trendCard(),
            const SizedBox(height: 14),
            _categoryCard(),
            const SizedBox(height: 18),
            _filters(),
            const SizedBox(height: 6),
            if (shown.isEmpty)
              const EmptyState('Expenses illa. + click panni add pannunga.'),
            for (final entry in groups.entries) ...[
              _dayHeader(entry.key, entry.value),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < entry.value.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 72),
                      _tile(entry.value[i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- sections

  Widget _hero() {
    final month = _num(summary['this_month_total']);
    final last = _num(summary['last_month_total']);
    final delta = last > 0 ? (month - last) / last * 100 : null;
    final up = (delta ?? 0) > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF97316), Color(0xFFDB2777)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF97316).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              const Text('This month',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              const Spacer(),
              if (delta != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 14,
                        color: up ? const Color(0xFFFFB4AB) : const Color(0xFFB9F6CA),
                      ),
                      const SizedBox(width: 3),
                      Text('${delta.abs().toStringAsFixed(0)}% vs last month',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fmtMoney(month),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _heroStat('Last month', fmtMoney(last)),
              _heroStat('All time', fmtMoney(_num(summary['total']))),
              _heroStat('Entries', '${summary['count'] ?? 0}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _trendCard() {
    final monthly = asMapList(summary['monthly']);
    if (monthly.isEmpty) return const SizedBox.shrink();
    final maxV = monthly.map((m) => _num(m['total'])).fold<double>(0, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Last 6 months',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 14),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < monthly.length; i++)
                    Expanded(
                      child: Builder(builder: (_) {
                        final v = _num(monthly[i]['total']);
                        final isLast = i == monthly.length - 1;
                        final h = maxV <= 0 ? 4.0 : (v / maxV * 78).clamp(4.0, 78.0);
                        final m = int.tryParse(
                                '${monthly[i]['month']}'.substring(5, 7)) ??
                            1;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(v > 0 ? fmtCompact(v) : '',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600)),
                            const SizedBox(height: 4),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              height: h,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: isLast
                                    ? scheme.primary
                                    : scheme.primary.withValues(alpha: 0.25),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(_months[m - 1],
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight:
                                        isLast ? FontWeight.w700 : FontWeight.w400,
                                    color: Colors.grey.shade700)),
                          ],
                        );
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryCard() {
    final rows = asMapList(
        summary[monthOnly ? 'by_category_month' : 'by_category']);
    final total = rows.fold<double>(0, (a, r) => a + _num(r['total']));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Spending by category',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: true, label: Text('Month')),
                    ButtonSegment(value: false, label: Text('All')),
                  ],
                  selected: {monthOnly},
                  onSelectionChanged: (s) => setState(() => monthOnly = s.first),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (rows.isEmpty || total <= 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Inga data illa',
                    style: TextStyle(color: Colors.grey.shade600)),
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    for (final r in rows)
                      Expanded(
                        flex: (_num(r['total']) / total * 1000).round().clamp(1, 1000),
                        child: Container(
                            height: 12, color: catOf('${r['category']}').color),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final r in rows.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: catOf('${r['category']}').color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(catOf('${r['category']}').label),
                      ),
                      Text(
                        '${(_num(r['total']) / total * 100).round()}%',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const SizedBox(width: 12),
                      Text(fmtMoney(_num(r['total'])),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: filter == 'ALL',
              onSelected: (_) => setState(() => filter = 'ALL'),
            ),
          ),
          for (final c in expenseCats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(c.icon,
                    size: 16, color: filter == c.key ? null : c.color),
                label: Text(c.label),
                selected: filter == c.key,
                onSelected: (_) => setState(() => filter = c.key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayHeader(String date, List<Map<String, dynamic>> items) {
    final total = items.fold<double>(0, (a, e) => a + _num(e['amount']));
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(_dayLabel(date),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                    fontSize: 13)),
          ),
          Text(fmtMoney(total),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> e) {
    final c = catOf('${e['category']}');
    final sub = [
      c.label,
      '${e['payment_method_label'] ?? e['payment_method']}',
      if (e['project_name'] != null) '${e['project_name']}',
    ].join('  •  ');

    return Dismissible(
      key: ValueKey('exp-${e['id']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(e),
      onDismissed: (_) => setState(() => expenses.remove(e)),
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: InkWell(
        onTap: () => _form(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(c.icon, color: c.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e['title']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(fmtMoney(_num(e['amount'])),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- form

/// Bottom-sheet add / edit form. Returns true when saved.
Future<bool> showExpenseForm(
  BuildContext context, {
  Map<String, dynamic>? expense,
  required List<Map<String, dynamic>> projects,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _ExpenseForm(expense: expense, projects: projects),
  );
  return saved ?? false;
}

class _ExpenseForm extends StatefulWidget {
  final Map<String, dynamic>? expense;
  final List<Map<String, dynamic>> projects;
  const _ExpenseForm({required this.expense, required this.projects});

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late String _category;
  late String _payment;
  late String _date;
  int? _project;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _amount = TextEditingController(
        text: e == null ? '' : _num(e['amount']).toString().replaceAll(RegExp(r'\.0$'), ''));
    _title = TextEditingController(text: e?['title']?.toString() ?? '');
    _notes = TextEditingController(text: e?['notes']?.toString() ?? '');
    _category = e?['category']?.toString() ?? 'OTHER';
    _payment = e?['payment_method']?.toString() ?? 'CASH';
    _date = e?['date']?.toString() ?? todayStr();
    final p = e?['project'];
    _project = widget.projects.any((x) => x['id'] == p) ? p as int : null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() => _date = picked.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {
      'title': _title.text.trim(),
      'amount': _amount.text.trim(),
      'category': _category,
      'payment_method': _payment,
      'date': _date,
      'notes': _notes.text.trim(),
      'project': _project,
    };
    try {
      if (_editing) {
        await Api.instance.patch('/api/expenses/${widget.expense!['id']}/', body);
      } else {
        await Api.instance.post('/api/expenses/', body);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete expense', 'Sure-a delete pannanuma?')) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await Api.instance.delete('/api/expenses/${widget.expense!['id']}/');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final cat = catOf(_category);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_editing ? 'Edit expense' : 'New expense',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: !_editing,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: cat.color),
                  hintText: '0',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'Amount podunga (0-ku mela)';
                  return null;
                },
              ),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Office rent, Tea & snacks',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Title is required' : null,
              ),
              _label('Category'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in expenseCats)
                    ChoiceChip(
                      avatar: Icon(c.icon,
                          size: 16, color: _category == c.key ? null : c.color),
                      label: Text(c.label),
                      selected: _category == c.key,
                      onSelected: (_) => setState(() => _category = c.key),
                    ),
                ],
              ),
              _label('Paid via'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in paymentOpts)
                    ChoiceChip(
                      label: Text(o.label),
                      selected: _payment == o.value,
                      onSelected: (_) => setState(() => _payment = o.value as String),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                  ),
                  child: Text(fmtDate(_date)),
                ),
              ),
              if (widget.projects.isNotEmpty) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: _project,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Project (optional)'),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('-- No project --')),
                    for (final p in widget.projects)
                      DropdownMenuItem<int?>(
                        value: p['id'] as int,
                        child: Text('${p['name']}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _project = v),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade900)),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  if (_editing) ...[
                    IconButton.outlined(
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: Colors.red.shade600,
                      tooltip: 'Delete',
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Text(_editing ? 'Save changes' : 'Add expense',
                              style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
