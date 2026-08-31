import 'package:flutter/material.dart';

import '../../models/poll.dart';
import '../../services/group_service.dart';
import '../../services/poll_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'poll_form_screen.dart';

/// Live group decision-making polls (e.g. picking a restaurant or
/// activity), backed by Supabase Realtime — create new polls, vote,
/// edit a poll's question/options, or delete it.
class VotingScreen extends StatefulWidget {
  const VotingScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  final _pollService = PollService();
  final _groupService = GroupService();
  late final Future<bool> _isOrganizerFuture = _groupService.isOrganizer(
    widget.tripId,
  );

  void _vote(Poll poll, PollOptionData option) {
    _pollService.vote(pollId: poll.id, optionId: option.id);
  }

  Future<void> _addPoll() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PollFormScreen(tripId: widget.tripId)),
    );
  }

  Future<void> _editPoll(Poll poll) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PollFormScreen(tripId: widget.tripId, initial: poll),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Voting',
              subtitle: 'Decide together on trip choices',
              trailing: IconButton(
                onPressed: _addPoll,
                icon: Icon(Icons.add_circle_rounded, color: context.colors.ink),
              ),
            ),
            Expanded(
              child: FutureBuilder<bool>(
                future: _isOrganizerFuture,
                builder: (context, organizerSnap) {
                  final isOrganizer = organizerSnap.data ?? false;
                  return StreamBuilder<List<Poll>>(
                    stream: _pollService.watchPolls(widget.tripId),
                    builder: (context, snapshot) {
                      final polls = snapshot.data ?? const <Poll>[];
                      if (polls.isEmpty) {
                        return _EmptyState(onCreate: _addPoll);
                      }
                      return ListView.builder(
                        padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                        itemCount: polls.length,
                        itemBuilder: (context, index) {
                          final poll = polls[index];
                          final totalVotes = poll.totalVotes;
                          return Container(
                            margin: EdgeInsets.only(bottom: 18),
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.colors.card,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: context.colors.ink.withValues(
                                    alpha: 0.05,
                                  ),
                                  blurRadius: 12,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        poll.question,
                                        style: TextStyle(
                                          color: context.colors.ink,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                    ),
                                    if (isOrganizer)
                                      GestureDetector(
                                        onTap: () => _editPoll(poll),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 10,
                                          ),
                                          child: Icon(
                                            Icons.edit_rounded,
                                            color: context.colors.muted,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                SizedBox(height: 14),
                                ...poll.options.map((option) {
                                  final ratio = totalVotes == 0
                                      ? 0.0
                                      : option.voteCount / totalVotes;
                                  final selected =
                                      poll.votedOptionId == option.id;
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: 10),
                                    child: GestureDetector(
                                      onTap: () => _vote(poll, option),
                                      child: Stack(
                                        children: [
                                          Container(
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: context.colors.surface,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: selected
                                                  ? Border.all(
                                                      color: context.colors.ink,
                                                      width: 1.5,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          FractionallySizedBox(
                                            widthFactor: ratio.clamp(0.0, 1.0),
                                            child: Container(
                                              height: 42,
                                              decoration: BoxDecoration(
                                                color:
                                                    (selected
                                                            ? context.colors.ink
                                                            : AppColors.accent)
                                                        .withValues(
                                                          alpha: 0.18,
                                                        ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 14,
                                              ),
                                              child: Row(
                                                children: [
                                                  if (selected)
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        right: 6,
                                                      ),
                                                      child: Icon(
                                                        Icons
                                                            .check_circle_rounded,
                                                        color:
                                                            context.colors.ink,
                                                        size: 16,
                                                      ),
                                                    ),
                                                  Expanded(
                                                    child: Text(
                                                      option.label,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color:
                                                            context.colors.ink,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 12.5,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '${option.voteCount}',
                                                    style: TextStyle(
                                                      color: context.colors.ink,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 12.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                SizedBox(height: 4),
                                Text(
                                  '$totalVotes votes',
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.how_to_vote_rounded,
              color: context.colors.muted,
              size: 44,
            ),
            const SizedBox(height: 16),
            Text(
              'No polls yet',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a poll to decide something together.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            Material(
              color: context.colors.ink,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onCreate,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'New Poll',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
