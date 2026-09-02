import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// UI-only comment thread on a community post.
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({super.key, required this.place});

  final String place;

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _Comment {
  _Comment(this.author, this.color, this.text, this.time);
  final String author;
  final Color color;
  final String text;
  final String time;
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _controller = TextEditingController();
  final _comments = [
    _Comment(
      'Arif Hakim',
      Color(0xFF5C6BC0),
      'Adding this to my list right now!',
      '1h ago',
    ),
    _Comment(
      'Sophia Tan',
      Color(0xFF11998E),
      'Went there last month, so worth it 🙌',
      '3h ago',
    ),
    _Comment(
      'Daniel Wong',
      Color(0xFFFFB347),
      'How early did you go to avoid crowds?',
      '5h ago',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _post() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _comments.insert(0, _Comment('You', AppColors.accent, text, 'now'));
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
            DetailHeader(title: 'Comments', subtitle: widget.place),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
                itemCount: _comments.length,
                itemBuilder: (context, index) {
                  final c = _comments[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: c.color,
                          child: Text(
                            c.author[0],
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.colors.card,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      c.author,
                                      style: TextStyle(
                                        color: context.colors.ink,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      c.time,
                                      style: TextStyle(
                                        color: context.colors.muted,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  c.text,
                                  style: TextStyle(
                                    color: context.colors.ink,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
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
                        hintText: 'Add a comment…',
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
                      onSubmitted: (_) => _post(),
                    ),
                  ),
                  SizedBox(width: 8),
                  Material(
                    color: context.colors.ink,
                    shape: CircleBorder(),
                    child: InkWell(
                      customBorder: CircleBorder(),
                      onTap: _post,
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
