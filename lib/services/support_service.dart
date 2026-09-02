import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A support request started from the Help Center's "Contact Support"
/// compose screen.
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

/// One message in a [SupportTicket]'s thread.
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

/// Backs the Help Center's "Contact Support" flow with real Supabase rows
/// instead of an actual outbound email — sending a message inserts a row,
/// and a reply (added by whoever is on support duty, via the Supabase Table
/// Editor) is a row too, so it shows up next time the customer opens the
/// thread here.
class SupportService {
  SupportService._();

  static final SupportService instance = SupportService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// The signed-in user's tickets, most recent first.
  Future<List<SupportTicket>> listMyTickets() async {
    final rows = await _client
        .from('support_tickets')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => SupportTicket.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Creates a new ticket with [subject] and an opening [message], and
  /// returns the new ticket's id.
  Future<String> createTicket({
    required String subject,
    required String message,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('createTicket called with no signed-in user');
    }
    final ticketRow = await _client
        .from('support_tickets')
        .insert({'user_id': user.id, 'subject': subject})
        .select()
        .single();
    final ticketId = ticketRow['id'] as String;
    await _client.from('support_messages').insert({
      'ticket_id': ticketId,
      'sender': 'customer',
      'body': message,
    });
    return ticketId;
  }

  /// All messages on [ticketId], oldest first.
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

  /// Adds a follow-up customer message to an existing ticket.
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
