/// One member's split-expense standing on a trip: how much they've paid
/// (derived from `expenses`) versus how much they still owe the
/// organizer (`trip_balances.owes_amount`, edited by the organizer).
class TripBalance {
  const TripBalance({
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    required this.isOrganizer,
    required this.paid,
    required this.owes,
  });

  final String userId;
  final String displayName;
  final int avatarColor;
  final bool isOrganizer;
  final double paid;
  final double owes;
}
