/// One member's split-expense standing on a trip: how much they've paid
/// (summed from `expenses`). The Expense Split screen derives everyone's
/// fair share and settle-up plan from these `paid` totals directly,
/// rather than a separately stored owed amount.
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
