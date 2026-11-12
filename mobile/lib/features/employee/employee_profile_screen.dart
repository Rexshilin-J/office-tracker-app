import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';
import 'employee_widgets.dart';

/// "My Profile": the employee's own details, read live from /api/auth/me/.
class MyProfileScreen extends StatefulWidget {
  final Session session;
  const MyProfileScreen({super.key, required this.session});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  static const Color _color = Color(0xFFDB2777);

  late Map<String, dynamic> me = widget.session.user ?? {};
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = asMap(await Api.instance.get('/api/auth/me/'));
      if (!mounted) return;
      setState(() {
        me = data;
        error = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          loading = false;
        });
      }
    }
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'OFFICE':
        return Icons.apartment;
      case 'REMOTE':
        return Icons.home_work;
      default:
        return Icons.swap_horiz;
    }
  }

  Widget _row(IconData icon, String label, String value) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _color.withValues(alpha: 0.12),
        child: Icon(icon, color: _color, size: 20),
      ),
      title: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      subtitle: Text(
        value.isEmpty ? 'Not set' : value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: value.isEmpty ? Colors.grey : Colors.black87,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = asText(me['username'], '?');
    final mode = asText(me['work_mode']);

    return Scaffold(
      appBar: gradientAppBar(title: const Text('My Profile'), color: _color),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null) ErrorBanner(error!),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: colorGradient(_color),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: Text(
                      name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.session.roleLabel,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  _row(Icons.badge_outlined, 'Employee ID', asText(me['employee_id'])),
                  _row(Icons.account_tree_outlined, 'Department', asText(me['department'])),
                  _row(Icons.work_outline, 'Designation', asText(me['designation'])),
                  _row(_modeIcon(mode), 'Work mode', mode.isEmpty ? '' : pretty(mode)),
                  _row(Icons.email_outlined, 'Email', asText(me['email'])),
                  _row(Icons.phone_outlined, 'Phone', asText(me['phone'])),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  if (await confirm(context, 'Logout', 'Logout pannanuma?')) {
                    if (context.mounted) Navigator.of(context).pop();
                    widget.session.logout();
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
