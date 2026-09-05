import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/locale_service.dart';
import '../../services/support_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/list_tile_card.dart';
import 'support_ticket_screen.dart';

const _supportEmail = 'tadmin082@gmail.com';

List<({String question, String answer})> _faqs() => [
  (question: tr('auth_faq_q1'), answer: tr('auth_faq_a1')),
  (question: tr('auth_faq_q2'), answer: tr('auth_faq_a2')),
  (question: tr('auth_faq_q3'), answer: tr('auth_faq_a3')),
  (question: tr('auth_faq_q4'), answer: tr('auth_faq_a4')),
  (question: tr('auth_faq_q5'), answer: tr('auth_faq_a5')),
];

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  late Future<List<SupportTicket>> _tickets;

  @override
  void initState() {
    super.initState();
    _tickets = SupportService.instance.listMyTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshTickets() {
    setState(() => _tickets = SupportService.instance.listMyTickets());
  }

  Future<void> _openContactSupport() async {
    final gmailComposeUri = Uri.https('mail.google.com', '/mail/', {
      'view': 'cm',
      'fs': '1',
      'to': _supportEmail,
      'su': 'TravelPlanner Support Request',
    });
    final launched = await launchUrl(
      gmailComposeUri,
      webOnlyWindowName: '_blank',
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          content: Text(
            '${tr('auth_couldnt_open_gmail_prefix')} $_supportEmail',
          ),
        ),
      );
    }
  }

  Future<void> _openTicket(SupportTicket ticket) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SupportTicketScreen(ticketId: ticket.id, subject: ticket.subject),
      ),
    );
    _refreshTickets();
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final faqs = _faqs();
    final filtered = q.isEmpty
        ? faqs
        : faqs.where((f) => f.question.toLowerCase().contains(q)).toList();

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('auth_help_center'),
              subtitle: tr('auth_help_center_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: context.colors.muted,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _query = v),
                            style: TextStyle(
                              color: context.colors.ink,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: tr('auth_search_topic_hint'),
                              hintStyle: TextStyle(color: context.colors.muted),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    tr('auth_faq_title'),
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        tr('auth_no_matching_questions'),
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12.5,
                        ),
                      ),
                    )
                  else
                    ...filtered.map((f) => _FaqTile(faq: f)),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('auth_still_need_help'),
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr('auth_support_reply_time'),
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        GradientButton(
                          label: tr('auth_contact_support'),
                          icon: Icons.mail_outline_rounded,
                          height: 48,
                          onPressed: _openContactSupport,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    tr('auth_your_requests'),
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<SupportTicket>>(
                    future: _tickets,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final tickets = snapshot.data ?? const [];
                      if (tickets.isEmpty) {
                        return Text(
                          tr('auth_havent_contacted_support'),
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12.5,
                          ),
                        );
                      }
                      return Column(
                        children: tickets
                            .map(
                              (t) => ListTileCard(
                                icon: Icons.chat_bubble_outline_rounded,
                                title: t.subject,
                                subtitle:
                                    '${tr('auth_sent_prefix')} ${_formatDate(t.createdAt)}',
                                onTap: () => _openTicket(t),
                              ),
                            )
                            .toList(),
                      );
                    },
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

class _FaqTile extends StatefulWidget {
  const _FaqTile({required this.faq});

  final ({String question, String answer}) faq;

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.faq.question,
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: context.colors.muted,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            widget.faq.answer,
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
