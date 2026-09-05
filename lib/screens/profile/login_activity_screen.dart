import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../models/login_activity.dart';
import '../../services/locale_service.dart';
import '../../services/login_activity_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/detail_header.dart';

/// Turns a raw Supabase error into a message worth showing the user.
/// `PGRST205` means the `login_activity` table hasn't been created yet on
/// this project (see supabase/migrations/0015_login_activity.sql) —
/// everything else falls back to a generic retry message.
String _friendlyError(Object e) {
  if (e is PostgrestException && e.code == 'PGRST205') {
    return tr('auth_login_activity_not_setup');
  }
  return tr('common_error_generic');
}

String _formatDateTime(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = dt.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year} · ${formatClockTime(local)}';
}

/// Recent sign-ins to the signed-in user's account (Privacy & Security >
/// Login Activity) — read-only, backed by `public.login_activity`, rows
/// written automatically on every real sign-in (see the
/// `onAuthStateChange` listener in `main.dart`).
class LoginActivityScreen extends StatefulWidget {
  const LoginActivityScreen({super.key});

  @override
  State<LoginActivityScreen> createState() => _LoginActivityScreenState();
}

class _LoginActivityScreenState extends State<LoginActivityScreen> {
  List<LoginActivityEntry>? _entries;
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final entries = await LoginActivityService.instance.list();
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      debugPrint('Failed to load login activity: $e');
      if (mounted) setState(() => _loadError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('auth_login_activity_title'),
              subtitle: tr('auth_login_activity_subtitle'),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _ErrorState(message: _loadError!, onRetry: _load);
    }
    final entries = _entries ?? [];
    if (entries.isEmpty) {
      return _EmptyState();
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isFirst = index == 0;
        return Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (isFirst ? AppColors.accent : context.colors.ink)
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.login_rounded,
                  color: isFirst ? AppColors.accent : context.colors.ink,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.deviceInfo ?? tr('auth_login_activity_title'),
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      _formatDateTime(entry.signedInAt),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isFirst)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tr('auth_login_activity_most_recent'),
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: Colors.redAccent),
            SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.ink, fontSize: 13.5),
            ),
            SizedBox(height: 20),
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: 18),
              label: Text(tr('auth_try_again')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 56,
              color: context.colors.muted,
            ),
            SizedBox(height: 16),
            Text(
              tr('auth_login_activity_empty'),
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 6),
            Text(
              tr('auth_login_activity_empty_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
