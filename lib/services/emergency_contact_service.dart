import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/emergency_contact.dart';

/// CRUD for the signed-in user's personal emergency contacts (family or
/// friends they add themselves) — separate from the Utilities module's
/// static list of official numbers (police, ambulance, etc.).
class EmergencyContactService {
  EmergencyContactService._();

  static final EmergencyContactService instance = EmergencyContactService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// The signed-in user's contacts, oldest-added first.
  Future<List<EmergencyContact>> list() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final rows = await _client
        .from('emergency_contacts')
        .select()
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => EmergencyContact.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> add({
    required String name,
    required String phone,
    String? relationship,
  }) {
    final user = _client.auth.currentUser;
    if (user == null) return Future.value();
    return _client.from('emergency_contacts').insert({
      'user_id': user.id,
      'name': name,
      'phone': phone,
      'relationship': _nullIfBlank(relationship),
    });
  }

  Future<void> update({
    required String id,
    required String name,
    required String phone,
    String? relationship,
  }) {
    return _client
        .from('emergency_contacts')
        .update({
          'name': name,
          'phone': phone,
          'relationship': _nullIfBlank(relationship),
        })
        .eq('id', id);
  }

  Future<void> delete(String id) {
    return _client.from('emergency_contacts').delete().eq('id', id);
  }

  String? _nullIfBlank(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}
