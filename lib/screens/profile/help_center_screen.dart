import 'package:flutter/material.dart';

import '../../services/support_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/list_tile_card.dart';
import 'contact_support_screen.dart';
import 'support_ticket_screen.dart';

const _faqs = [
  (
    question: 'How do I create a new trip?',
    answer: 'Go to the Trips tab and tap the "+" button, or use "New Trip" '
        'from the home dashboard\'s quick actions. Fill in your destination, '
        'dates, and interests, then let the AI planner build your itinerary.',
  ),
  (
    question: 'Can I edit my itinerary after it\'s created?',
    answer: 'Yes — open your trip, tap the edit icon to update trip details, '
        'or use "Edit Schedule" from the tools grid to add, remove, or '
        'reorder stops day by day.',
  ),
  (
    question: 'How does the budget tracker work?',
    answer: 'Set a total budget in Budget Planner, then log expenses under '
        'each category. Split Expenses divides costs among your travel '
        'group and tracks who owes the trip organizer.',
  ),
  (
    question: 'Does the app work offline?',
    answer: 'Core planning features work without a connection, but live '
        'data like weather and bus departures needs an internet connection '
        'to refresh.',
  ),
  (
    question: 'How do I invite friends to a trip?',
    answer: 'From Group Travel, tap "Invite Member" to generate a join '
        'code, or share it directly. Friends enter the code from "Join a '
        'Trip" on the home dashboard.',
  ),
];

/// Help center: an FAQ list plus a contact-support flow backed by real
/// [SupportTicket] rows (see `support_service.dart`).
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ContactSupportScreen()));
    _refreshTickets();
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _faqs
        : _faqs.where((f) => f.question.toLowerCase().contains(q)).toList();

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Help Center',
              subtitle: 'Answers to common questions',
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
                              hintText: 'Search for a topic…',
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
                    'Frequently Asked Questions',
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
                        'No matching questions — try Contact Support below.',
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
                          'Still need help?',
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Our support team typically replies within a day.',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        GradientButton(
                          label: 'Contact Support',
                          icon: Icons.mail_outline_rounded,
                          height: 48,
                          onPressed: _openContactSupport,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Your Requests',
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
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
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
                          'You haven\'t contacted support yet.',
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
                                subtitle: 'Sent ${_formatDate(t.createdAt)}',
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
