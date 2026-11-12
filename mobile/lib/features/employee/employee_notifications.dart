import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../shared/ui.dart';
import 'employee_widgets.dart';

/// App-bar bell with an unread badge. Polls a very cheap count endpoint.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with LivePolling<NotificationBell> {
  int unread = 0;

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
      final data = asMap(await Api.instance.get('/api/notifications/unread-count/'));
      if (mounted) setState(() => unread = asInt(data['count']));
    } on ApiException catch (_) {
      // The bell is decoration: stay quiet if the network blips.
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_rounded),
      ),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        );
        if (mounted) refresh();
      },
    );
  }
}

/// Task assignments, project updates and announcements.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with LivePolling<NotificationsScreen> {
  static const Color _color = Color(0xFF7C3AED);

  List<Map<String, dynamic>> items = [];
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
      final data = await Api.instance.get('/api/notifications/');
      if (!mounted) return;
      setState(() {
        items = asMapList(data);
        error = null;
        loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    if (n['is_read'] == true) return;
    setState(() => n['is_read'] = true); // instant feedback
    await guarded(
      context,
      () => Api.instance.post('/api/notifications/${n['id']}/read/'),
    );
  }

  Future<void> _markAll() async {
    final ok = await guarded(
      context,
      () => Api.instance.post('/api/notifications/read-all/'),
    );
    if (ok) await refresh();
  }

  IconData _icon(String kind) {
    switch (kind) {
      case 'TASK':
        return Icons.assignment_ind;
      case 'PROJECT':
        return Icons.folder_special;
      default:
        return Icons.campaign;
    }
  }

  Color _tint(String kind) {
    switch (kind) {
      case 'TASK':
        return const Color(0xFF0D9488);
      case 'PROJECT':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFFF97316);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = items.any((n) => n['is_read'] != true);

    return Scaffold(
      appBar: gradientAppBar(
        title: const Text('Notifications'),
        color: _color,
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAll,
              child: const Text('Mark all read',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: !loaded && error == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null) ErrorBanner(error!),
                  if (items.isEmpty) const EmptyState("You're all caught up."),
                  for (final n in items) _tile(n),
                ],
              ),
            ),
    );
  }

  Widget _tile(Map<String, dynamic> n) {
    final unread = n['is_read'] != true;
    final kind = asText(n['kind']);
    final tint = _tint(kind);
    final message = asText(n['message']);

    return Card(
      color: unread ? tint.withValues(alpha: 0.06) : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _markRead(n),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: tint.withValues(alpha: 0.15),
                child: Icon(_icon(kind), color: tint, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            asText(n['title']),
                            style: TextStyle(
                              fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: tint,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(message, style: TextStyle(color: Colors.grey.shade800)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${pretty(kind)}  •  ${timeAgo(n['created_at'])}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
