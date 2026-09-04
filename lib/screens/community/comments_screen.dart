import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
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
  // User-added comments only — the seed comments below are recomputed via
  // `_seedComments()` on every build so they retranslate with the app's
  // language, instead of being frozen (like a `final` field would be) at
  // whichever language was active when this screen was first opened.
  final _userComments = <_Comment>[];

  List<_Comment> _seedComments() => [
    _Comment(
      tr('community_author_arif_hakim'),
      Color(0xFF5C6BC0),
      tr('community_comment_1'),
      tr('community_time_1h_ago'),
    ),
    _Comment(
      tr('community_author_sophia_tan'),
      Color(0xFF11998E),
      tr('community_comment_2'),
      tr('community_time_3h_ago'),
    ),
    _Comment(
      tr('community_author_daniel_wong'),
      Color(0xFFFFB347),
      tr('community_comment_3'),
      tr('community_time_5h_ago'),
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
      _userComments.insert(
        0,
        _Comment(tr('community_comment_you'), AppColors.accent, text, tr('community_time_now')),
      );
      _controller.clear();
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final comments = [..._userComments, ..._seedComments()];
    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('community_comments_title'),
              subtitle: widget.place,
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
                itemCount: comments.length,
                itemBuilder: (context, index) {
                  final c = comments[index];
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
                        hintText: tr('community_add_comment_hint'),
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
