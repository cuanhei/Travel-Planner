import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String _generateCode({int length = 6}) {
  final random = Random();
  return List.generate(
    length,
    (_) => _codeChars[random.nextInt(_codeChars.length)],
  ).join();
}

class _JoinRequest {
  _JoinRequest({required this.name, required this.color, required this.timeAgo});
  final String name;
  final Color color;
  final String timeAgo;
}

/// UI-only "invite a member" flow: generates a random join code the
/// traveler can share so a friend can add themselves to this trip's
/// group. No backend or real invite link — copying uses the system
/// clipboard, which is the only "live" behavior here.
class InviteMemberScreen extends StatefulWidget {
  const InviteMemberScreen({super.key, required this.tripName});

  final String tripName;

  @override
  State<InviteMemberScreen> createState() => _InviteMemberScreenState();
}

class _InviteMemberScreenState extends State<InviteMemberScreen> {
  String _code = _generateCode();

  final _requests = [
    _JoinRequest(
      name: 'Sarah Lim',
      color: const Color(0xFFFF7A59),
      timeAgo: '5 min ago',
    ),
    _JoinRequest(
      name: 'Danial Yusof',
      color: const Color(0xFF2E9CCA),
      timeAgo: '1 hour ago',
    ),
  ];

  void _regenerate() => setState(() => _code = _generateCode());

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: const Text('Code copied to clipboard'),
      ),
    );
  }

  void _approve(_JoinRequest request) {
    setState(() => _requests.remove(request));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text('${request.name} added to the group'),
      ),
    );
  }

  void _reject(_JoinRequest request) {
    setState(() => _requests.remove(request));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text('${request.name}\'s request was declined'),
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
                        Text(
                          _code,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Expires in 24 hours',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 11.5,
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
                                onTap: _regenerate,
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
                      if (_requests.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_requests.length}',
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
                  if (_requests.isEmpty)
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
                    ..._requests.map(
                      (r) => _RequestTile(
                        request: r,
                        onApprove: () => _approve(r),
                        onReject: () => _reject(r),
                      ),
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
                    subtitle: 'Send it to your friend however you like — chat, text, or in person.',
                  ),
                  _StepTile(
                    number: '2',
                    title: 'They enter it in the app',
                    subtitle: 'From "Join a Trip", they type in the 6-character code.',
                  ),
                  _StepTile(
                    number: '3',
                    title: 'They\'re added automatically',
                    subtitle: 'Your friend appears in the group and can see the shared itinerary.',
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

  final _JoinRequest request;
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
            backgroundColor: request.color,
            child: Text(
              request.name[0],
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
                  request.name,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Wants to join · ${request.timeAgo}',
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 11.5,
                  ),
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
