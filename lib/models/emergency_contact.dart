import 'package:flutter/foundation.dart';

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
