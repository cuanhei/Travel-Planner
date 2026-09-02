import 'package:flutter/material.dart';

import '../../services/support_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import 'support_ticket_screen.dart';

const _supportEmail = 'clin03631@gmail.com';

/// Compose screen for a new support request, styled like an email client's
/// "New Message" — a fixed "To", a subject line, and a message body.
///
/// There's no real outbound email behind this: sending creates a
/// [SupportTicket] row instead, and [SupportTicketScreen] is where the
/// customer reads it and any reply.
class ContactSupportScreen extends StatefulWidget {
  const ContactSupportScreen({super.key});

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      _showSnack('Please fill in a subject and a message', error: true);
      return;
    }

    setState(() => _sending = true);
    try {
      final ticketId = await SupportService.instance.createTicket(
        subject: subject,
        message: message,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              SupportTicketScreen(ticketId: ticketId, subject: subject),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack('Something went wrong. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.redAccent : context.colors.ink,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Contact Support',
              subtitle: 'We usually reply within a day',
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.card,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      _ComposeRow(
                        label: 'To',
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _supportEmail,
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 15,
                              color: context.colors.muted,
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: context.colors.surface),
                      _ComposeRow(
                        label: 'Subject',
                        child: TextField(
                          controller: _subjectController,
                          style: TextStyle(
                            color: context.colors.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration.collapsed(
                            hintText: 'What do you need help with?',
                            hintStyle: TextStyle(color: context.colors.muted),
                          ),
                        ),
                      ),
                      Divider(height: 1, color: context.colors.surface),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _messageController,
                          minLines: 8,
                          maxLines: 16,
                          style: TextStyle(
                            color: context.colors.ink,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                          decoration: InputDecoration.collapsed(
                            hintText: 'Describe your question or issue…',
                            hintStyle: TextStyle(color: context.colors.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: GradientButton(
                label: 'Send',
                icon: Icons.send_rounded,
                onPressed: _send,
                loading: _sending,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposeRow extends StatelessWidget {
  const _ComposeRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                color: context.colors.muted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
