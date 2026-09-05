import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.createdAt,
  });

  final String id;
  final String subject;
  final DateTime createdAt;

  factory SupportTicket.fromRow(Map<String, dynamic> row) => SupportTicket(
    id: row['id'] as String,
    subject: row['subject'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

enum SupportSender { customer, support }

@immutable
class SupportMessage {
  const SupportMessage({
    required this.sender,
    required this.body,
    required this.createdAt,
  });

  final SupportSender sender;
  final String body;
  final DateTime createdAt;

  factory SupportMessage.fromRow(Map<String, dynamic> row) => SupportMessage(
    sender: (row['sender'] as String) == 'support'
        ? SupportSender.support
        : SupportSender.customer,
    body: row['body'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

class SupportService {
  SupportService._();

  static final SupportService instance = SupportService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<SupportTicket>> listMyTickets() async {
    final rows = await _client
        .from('support_tickets')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => SupportTicket.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<SupportMessage>> listMessages(String ticketId) async {
    final rows = await _client
        .from('support_messages')
        .select()
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => SupportMessage.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendFollowUp({
    required String ticketId,
    required String message,
  }) {
    return _client.from('support_messages').insert({
      'ticket_id': ticketId,
      'sender': 'customer',
      'body': message,
    });
  }
}
