/// The signed-in user's identity — backed by `profiles`. Avatars in this
/// app are a solid color (`avatar_color`) with the name's initial, not an
/// uploaded photo; there's no `avatar_url` upload feature (yet).
class Profile {
  const Profile({required this.name, required this.email, this.avatarColor});

  final String name;
  final String email;
  final int? avatarColor;

  /// Prefers `full_name`, falling back to `display_name`, then a generic
  /// placeholder — mirrors the fallback chain the Profile tab already used.
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
