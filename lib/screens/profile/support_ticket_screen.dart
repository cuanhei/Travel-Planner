import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../services/support_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

class SupportTicketScreen extends StatefulWidget {
  const SupportTicketScreen({
    super.key,
    required this.ticketId,
    required this.subject,
  });

  final String ticketId;
  final String subject;

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  final _controller = TextEditingController();
  Future<List<SupportMessage>>? _messages;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _messages = SupportService.instance.listMessages(widget.ticketId);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await SupportService.instance.sendFollowUp(
        ticketId: widget.ticketId,
        message: text,
      );
      if (!mounted) return;
      _controller.clear();
      FocusScope.of(context).unfocus();
      _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          content: Text(tr('common_error_generic')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: widget.subject,
              subtitle: tr('auth_support_request_word'),
              trailing: IconButton(
                onPressed: _refresh,
                icon: Icon(Icons.refresh_rounded, color: context.colors.ink),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<SupportMessage>>(
                future: _messages,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        tr('auth_couldnt_load_conversation'),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  final messages = snapshot.data ?? const [];
                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        tr('auth_no_messages_yet'),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _MessageBubble(message: messages[index]),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: context.colors.ink, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: tr('auth_send_followup_hint'),
                        hintStyle: TextStyle(color: context.colors.muted),
                        filled: true,
                        fillColor: context.colors.card,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: context.colors.ink,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending ? null : _send,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _sending
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                      ),
                    ),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final isCustomer = message.sender == SupportSender.customer;
    return Align(
      alignment: isCustomer ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isCustomer ? context.colors.ink : context.colors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCustomer ? tr('auth_you_word') : tr('auth_support_team_word'),
              style: TextStyle(
                color: isCustomer
                    ? Colors.white.withValues(alpha: 0.8)
                    : context.colors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.body,
              style: TextStyle(
                color: isCustomer ? Colors.white : context.colors.ink,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
