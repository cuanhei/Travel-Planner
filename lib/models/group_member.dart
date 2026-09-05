/// A trip member, joined from `trip_members` + `profiles`.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    required this.role,
    required this.joinedAt,
    this.nickname,
  });

  final String userId;
  final String displayName;
  final int avatarColor;
  final String role;
  final DateTime joinedAt;

  /// This member's own alias for this trip's Group Chat (set via
  /// "Change Nickname"), or null to just show [displayName].
  final String? nickname;

  bool get isOrganizer => role == 'organizer';

  /// What to actually show for this member: their nickname if they've
  /// set one for this trip, otherwise their profile name.
  String get label =>
      (nickname != null && nickname!.isNotEmpty) ? nickname! : displayName;

  factory GroupMember.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>;
    return GroupMember(
      userId: map['user_id'] as String,
      displayName: profile['display_name'] as String,
      avatarColor: profile['avatar_color'] as int,
      role: map['role'] as String,
      joinedAt: DateTime.parse(map['joined_at'] as String),
      nickname: map['nickname'] as String?,
    );
  }
}
