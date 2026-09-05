import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/join_request.dart';
import '../../services/group_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

class InviteMemberScreen extends StatefulWidget {
  const InviteMemberScreen({
    super.key,
    required this.tripId,
    required this.tripName,
  });

  final String tripId;
  final String tripName;

  @override
  State<InviteMemberScreen> createState() => _InviteMemberScreenState();
}

const _inviteCodeValidity = Duration(minutes: 1);

class _InviteMemberScreenState extends State<InviteMemberScreen> {
  final _groupService = GroupService();
  String? _code;
  bool _generating = false;
  DateTime? _expiresAt;
  Duration _remaining = Duration.zero;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _tickCountdown();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickCountdown(),
    );
  }

  void _tickCountdown() {
    final expiresAt = _expiresAt;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(DateTime.now());
    setState(
      () => _remaining = remaining.isNegative ? Duration.zero : remaining,
    );
    if (remaining.isNegative || remaining == Duration.zero) {
      _countdownTimer?.cancel();
    }
  }

  String _formatRemaining(Duration d) {
    final seconds = d.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _regenerate() async {
    _countdownTimer?.cancel();
    setState(() => _generating = true);
    try {
      final code = await _groupService.generateInviteCode(widget.tripId);
      if (!mounted) return;
      setState(() {
        _code = code;
        _generating = false;
        _expiresAt = DateTime.now().add(_inviteCodeValidity);
        _remaining = _inviteCodeValidity;
      });
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')),
      );
    }
  }

  Future<void> _copyCode() async {
    if (_code == null) return;
    await Clipboard.setData(ClipboardData(text: _code!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: const Text('Code copied to clipboard'),
      ),
    );
  }

  Future<void> _rejectWithReason(JoinRequest request) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Decline ${request.displayName}\'s request',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 15.5,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: TextStyle(color: dialogContext.colors.ink),
          decoration: InputDecoration(
            hintText: 'Let them know why (optional)',
            filled: true,
            fillColor: dialogContext.colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    await _decide(request, false, reason: reason.isEmpty ? null : reason);
  }

  Future<void> _decide(
    JoinRequest request,
    bool approve, {
    String? reason,
  }) async {
    try {
      await _groupService.decideJoinRequest(
        requestId: request.id,
        approve: approve,
        reason: reason,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text(
          approve
              ? '${request.displayName} added to the group'
              : "${request.displayName}'s request was declined",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Invite Member',
              subtitle: 'Add someone to ${widget.tripName}',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 32,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: AppColors.horizon,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.horizon.last.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'GROUP INVITE CODE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        _generating
                            ? const SizedBox(
                                height: 46,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              )
                            : Text(
                                _code ?? '——————',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 8,
                                ),
                              ),
                        const SizedBox(height: 4),
                        Text(
                          _generating
                              ? ' '
                              : (_remaining == Duration.zero
                                    ? 'Code expired — tap refresh for a new one'
                                    : 'Expires in ${_formatRemaining(_remaining)}'),
                          style: TextStyle(
                            color: _remaining == Duration.zero
                                ? const Color(0xFFFFD54F)
                                : Colors.white.withValues(alpha: 0.75),
                            fontSize: 11.5,
                            fontWeight: _remaining == Duration.zero
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: _copyCode,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.copy_rounded,
                                          size: 16,
                                          color: context.colors.ink,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Copy Code',
                                          style: TextStyle(
                                            color: context.colors.ink,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Material(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: _generating ? null : _regenerate,
                                child: const Padding(
                                  padding: EdgeInsets.all(13),
                                  child: Icon(
                                    Icons.refresh_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  StreamBuilder<List<JoinRequest>>(
                    stream: _groupService.watchJoinRequests(widget.tripId),
                    builder: (context, snapshot) {
                      final requests = snapshot.data ?? const <JoinRequest>[];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Join Requests',
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              if (requests.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${requests.length}',
                                    style: const TextStyle(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (requests.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: context.colors.card,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'No pending requests right now.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            )
                          else
                            ...requests.map(
                              (r) => _RequestTile(
                                request: r,
                                onApprove: () => _decide(r, true),
                                onReject: () => _rejectWithReason(r),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'How it works',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _StepTile(
                    number: '1',
                    title: 'Share this code',
                    subtitle:
                        'Send it to your friend however you like — chat, text, or in person.',
                  ),
                  _StepTile(
                    number: '2',
                    title: 'They enter it in the app',
                    subtitle:
                        'From "Join a Trip", they type in the 6-character code.',
                  ),
                  _StepTile(
                    number: '3',
                    title: 'You approve their request',
                    subtitle:
                        'They appear here as a join request — approve it and they\'re in the group.',
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final JoinRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Color(request.avatarColor),
            child: Text(
              request.displayName[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.displayName,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Wants to join',
                  style: TextStyle(color: context.colors.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            icon: Icons.close_rounded,
            color: Colors.redAccent,
            onTap: onReject,
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            icon: Icons.check_rounded,
            color: const Color(0xFF11998E),
            onTap: onApprove,
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final String number;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
