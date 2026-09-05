class TripSettlement {
  const TripSettlement({
    required this.id,
    required this.tripId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String tripId;
  final String fromUserId;
  final String toUserId;
  final double amount;
  final String createdBy;
  final DateTime createdAt;

  factory TripSettlement.fromMap(Map<String, dynamic> map) {
    return TripSettlement(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      fromUserId: map['from_user_id'] as String,
      toUserId: map['to_user_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
