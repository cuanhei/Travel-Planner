import 'package:flutter/foundation.dart';

/// One entry in the signed-in user's personal emergency-contacts list
/// (family/friends they add themselves) — see `emergency_contact_service.dart`.
@immutable
class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.relationship,
  });

  final String id;
  final String name;
  final String phone;
  final String? relationship;

  factory EmergencyContact.fromRow(Map<String, dynamic> row) =>
      EmergencyContact(
        id: row['id'] as String,
        name: row['name'] as String,
        phone: row['phone'] as String,
        relationship: row['relationship'] as String?,
      );
}
