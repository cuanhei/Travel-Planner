import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/chat_time.dart';
import '../../widgets/detail_header.dart';

/// One message reduced to just what search needs to show/filter/jump
/// to — built by Group Chat and Direct Message screens from their own
/// message types so [ChatSearchScreen] doesn't need to know about
/// either.
class SearchableChatMessage {
  const SearchableChatMessage({
    required this.id,
    required this.senderLabel,
    required this.body,
    required this.createdAt,
    required this.hasAttachment,
  });

  final String id;
  final String senderLabel;
  final String? body;
  final DateTime createdAt;
  final bool hasAttachment;
}

/// Search this conversation's history by keyword and/or date range —
/// entirely in-memory over the messages already loaded by the caller
/// (a trip's chat history is small enough that a server round-trip
/// isn't worth it). Tapping a result pops this screen back with that
/// message's id, so the caller can scroll to and highlight it.
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({
    super.key,
    required this.subtitle,
    required this.messages,
  });

  final String subtitle;
  final List<SearchableChatMessage> messages;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _controller = TextEditingController();
  String _keyword = '';
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A separate single-date picker per boundary rather than one
  /// combined range picker — each gets its own tappable year header for
  /// jumping straight to any year, instead of only being able to step
  /// month-by-month through the range picker's one visible calendar.
  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: _endDate ?? now,
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
    });
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? now,
      firstDate: _startDate ?? DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _endDate = picked;
      if (_startDate != null && _startDate!.isAfter(picked)) {
        _startDate = picked;
      }
    });
  }

  List<SearchableChatMessage> get _results {
    final keyword = _keyword.trim().toLowerCase();
    final start = _startDate;
    final end = _endDate;
    return widget.messages.where((m) {
      if (keyword.isNotEmpty &&
          !(m.body ?? '').toLowerCase().contains(keyword)) {
        return false;
      }
      if (start != null || end != null) {
        // .toLocal() matters: createdAt is UTC (as parsed from
        // Supabase), and comparing its raw year/month/day against a
        // locally-picked calendar date silently shifts the boundary by
        // a day for anyone not at UTC+0.
        final local = m.createdAt.toLocal();
        final day = DateTime(local.year, local.month, local.day);
        if (start != null &&
            day.isBefore(DateTime(start.year, start.month, start.day))) {
          return false;
        }
        if (end != null &&
            day.isAfter(DateTime(end.year, end.month, end.day))) {
          return false;
        }
      }
      return true;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  String _shortDate(DateTime d) => formatChatDateTime(d).split(',').first;

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final hasFilter =
        _keyword.isNotEmpty || _startDate != null || _endDate != null;

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Search', subtitle: widget.subtitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                children: [
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: (v) => setState(() => _keyword = v),
                    style: TextStyle(color: context.colors.ink, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search messages…',
                      hintStyle: TextStyle(color: context.colors.muted),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: context.colors.muted,
                      ),
                      filled: true,
                      fillColor: context.colors.card,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickStartDate,
                          icon: const Icon(
                            Icons.calendar_month_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _startDate == null
                                ? 'From'
                                : _shortDate(_startDate!),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickEndDate,
                          icon: const Icon(
                            Icons.calendar_month_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _endDate == null ? 'To' : _shortDate(_endDate!),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (_startDate != null || _endDate != null)
                        IconButton(
                          onPressed: () => setState(() {
                            _startDate = null;
                            _endDate = null;
                          }),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        hasFilter
                            ? 'No messages found'
                            : 'Type to search this chat',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final m = results[index];
                        return Material(
                          color: context.colors.card,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.of(context).pop(m.id),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          m.senderLabel,
                                          style: TextStyle(
                                            color: context.colors.ink,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        formatChatDateTime(m.createdAt),
                                        style: TextStyle(
                                          color: context.colors.muted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    m.body ??
                                        (m.hasAttachment
                                            ? '📎 Attachment'
                                            : ''),
                                    style: TextStyle(
                                      color: context.colors.muted,
                                      fontSize: 12.5,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
