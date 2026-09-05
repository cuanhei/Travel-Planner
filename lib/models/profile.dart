class Profile {
  const Profile({required this.name, required this.email, this.avatarColor});

  final String name;
  final String email;
  final int? avatarColor;

  factory Profile.fromMap(Map<String, dynamic> map, {String? fallbackEmail}) {
    final fullName = (map['full_name'] as String?)?.trim();
    final name = fullName?.isNotEmpty == true
        ? fullName!
        : ((map['display_name'] as String?) ?? 'Traveler');
    return Profile(
      name: name,
      email: (map['email'] as String?) ?? fallbackEmail ?? '',
      avatarColor: map['avatar_color'] as int?,
    );
  }

  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';
}
