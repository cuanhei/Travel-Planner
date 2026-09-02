import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/coming_soon.dart';
import 'add_post_screen.dart';
import 'comments_screen.dart';

class Review {
  Review({
    required this.author,
    required this.avatarColor,
    required this.rating,
    required this.date,
    required this.text,
  });

  final String author;
  final Color avatarColor;
  final double rating;
  final String date;
  final String text;
}

class Post {
  Post({
    required this.author,
    required this.avatarColor,
    required this.place,
    required this.time,
    required this.caption,
    required this.gradient,
    required this.icon,
    required this.likes,
    required this.comments,
  });

  final String author;
  final Color avatarColor;
  final String place;
  final String time;
  final String caption;
  final List<Color> gradient;
  final IconData icon;
  final int likes;
  final int comments;
}

final feedPosts = [
  Post(
    author: 'Mei Ling',
    avatarColor: Color(0xFFFF7A59),
    place: 'Chew Jetty, George Town',
    time: '2h ago',
    caption:
        'Sunset over the stilt houses was unreal 😍 definitely worth the '
        'early evening visit, way less crowded too.',
    gradient: AppColors.horizon,
    icon: Icons.holiday_village_rounded,
    likes: 128,
    comments: 14,
  ),
  Post(
    author: 'Arif Hakim',
    avatarColor: Color(0xFF5C6BC0),
    place: 'Gurney Drive Hawker Centre',
    time: '5h ago',
    caption:
        'Char kway teow here is elite. Went back for seconds, no regrets. '
        'Bring cash, most stalls don\'t take cards.',
    gradient: AppColors.sunset,
    icon: Icons.restaurant_rounded,
    likes: 96,
    comments: 21,
  ),
  Post(
    author: 'Sophia Tan',
    avatarColor: Color(0xFF11998E),
    place: 'Penang Hill',
    time: '1d ago',
    caption:
        'The funicular queue was long but the view at the top made up for '
        'it completely. Go early morning to beat the crowd and the heat.',
    gradient: AppColors.lagoon,
    icon: Icons.terrain_rounded,
    likes: 203,
    comments: 32,
  ),
];

/// "Community" bottom-nav tab: a simple travel-experience feed.
class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  Future<void> _addPost() async {
    final post = await Navigator.of(
      context,
    ).push<Post>(MaterialPageRoute(builder: (_) => const AddPostScreen()));
    if (post == null) return;
    setState(() => feedPosts.insert(0, post));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('common_nav_community'),
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Material(
                color: context.colors.ink,
                shape: CircleBorder(),
                child: InkWell(
                  customBorder: CircleBorder(),
                  onTap: _addPost,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            tr('community_subtitle'),
            style: TextStyle(color: context.colors.muted, fontSize: 13.5),
          ),
          SizedBox(height: 20),
          ...feedPosts.map((p) => _PostCard(post: p)),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: post.avatarColor,
                child: Text(
                  post.author[0],
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      '${post.place} · ${post.time}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            post.caption,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          SizedBox(height: 12),
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: post.gradient),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(
              post.icon,
              color: Colors.white.withValues(alpha: 0.9),
              size: 40,
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              _PostAction(
                icon: Icons.favorite_border_rounded,
                label: '${post.likes}',
                onTap: () => showComingSoon(context, tr('community_like')),
              ),
              SizedBox(width: 18),
              _PostAction(
                icon: Icons.mode_comment_outlined,
                label: '${post.comments}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CommentsScreen(place: post.place),
                  ),
                ),
              ),
              Spacer(),
              GestureDetector(
                onTap: () => showComingSoon(context, tr('community_share')),
                child: Icon(
                  Icons.share_outlined,
                  color: context.colors.muted,
                  size: 19,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: context.colors.muted, size: 19),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
