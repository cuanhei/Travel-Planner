class TripBalance {
  const TripBalance({
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    required this.isOrganizer,
    required this.paid,
  });

  final String userId;
  final String displayName;
  final int avatarColor;
  final bool isOrganizer;
  final double paid;
}
