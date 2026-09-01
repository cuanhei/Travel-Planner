import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

class _Message {
  _Message(this.sender, this.color, this.text, this.mine);
  final String sender;
  final Color color;
  final String text;
  final bool mine;
}

/// UI-only group chat with a static seed conversation plus local send.
class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _controller = TextEditingController();
  final _messages = [
    _Message(
      'Mei Ling',
      Color(0xFF5C6BC0),
      'Should we do Gurney Drive on day 2 or day 3?',
      false,
    ),
    _Message(
      'Arif Hakim',
      Color(0xFF11998E),
      'Day 2 works better, less crowded on weekdays',
      false,
    ),
    _Message(
      'Alex Tan',
      AppColors.accent,
      'Sounds good, updating the itinerary now 👍',
      true,
    ),
    _Message(
      'Mei Ling',
      Color(0xFF5C6BC0),
      'Also can we add Chew Jetty somewhere?',
      false,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_Message('Alex Tan', AppColors.accent, text, true));
      _controller.clear();
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Group Chat', subtitle: 'Penang Adventure'),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final m = _messages[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: m.mine
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!m.mine) ...[
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: m.color,
                            child: Text(
                              m.sender[0],
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Column(
                            crossAxisAlignment: m.mine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!m.mine)
                                Padding(
                                  padding: EdgeInsets.only(bottom: 3, left: 4),
                                  child: Text(
                                    m.sender,
                                    style: TextStyle(
                                      color: context.colors.muted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: m.mine
                                      ? context.colors.ink
                                      : context.colors.card,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  m.text,
                                  style: TextStyle(
                                    color: m.mine
                                        ? Colors.white
                                        : context.colors.ink,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: context.colors.ink, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Message the group…',
                        hintStyle: TextStyle(color: context.colors.muted),
                        filled: true,
                        fillColor: context.colors.card,
                        contentPadding: EdgeInsets.symmetric(
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
                  SizedBox(width: 8),
                  Material(
                    color: context.colors.ink,
                    shape: CircleBorder(),
                    child: InkWell(
                      customBorder: CircleBorder(),
                      onTap: _send,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
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
