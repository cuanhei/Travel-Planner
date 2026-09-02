import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'poll_form_screen.dart';

class PollOption {
  PollOption(this.label, this.votes);
  final String label;
  int votes;
}

class Poll {
  Poll(this.question, this.options);
  final String question;
  final List<PollOption> options;
  int? votedIndex;
}

/// Group decision-making polls (e.g. picking a restaurant or activity) —
/// create new polls, vote, edit a poll's question/options, or delete it.
class VotingScreen extends StatefulWidget {
  const VotingScreen({super.key});

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  final _polls = [
    Poll('Where should we have dinner on Day 2?', [
      PollOption('Gurney Drive Hawker Centre', 2),
      PollOption('Hin Bus Depot food stalls', 1),
      PollOption('A proper sit-down restaurant', 0),
    ]),
    Poll('Should we add Penang Hill to the itinerary?', [
      PollOption('Yes, add it', 1),
      PollOption('No, skip it', 0),
    ]),
  ];

  void _vote(Poll poll, int index) {
    setState(() {
      if (poll.votedIndex != null) {
        poll.options[poll.votedIndex!].votes -= 1;
      }
      poll.options[index].votes += 1;
      poll.votedIndex = index;
    });
  }

  Future<void> _addPoll() async {
    final result = await Navigator.of(
      context,
    ).push<PollFormResult>(MaterialPageRoute(builder: (_) => const PollFormScreen()));
    if (result == null || result.deleted || !mounted) return;
    setState(() => _polls.add(result.poll!));
  }

  Future<void> _editPoll(int index) async {
    final result = await Navigator.of(context).push<PollFormResult>(
      MaterialPageRoute(builder: (_) => PollFormScreen(initial: _polls[index])),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.deleted) {
        _polls.removeAt(index);
      } else {
        _polls[index] = result.poll!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('group_action_voting_title'),
              subtitle: tr('group_voting_subtitle'),
              trailing: IconButton(
                onPressed: _addPoll,
                icon: Icon(Icons.add_circle_rounded, color: context.colors.ink),
              ),
            ),
            Expanded(
              child: _polls.isEmpty
                  ? _EmptyState(onCreate: _addPoll)
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: _polls.length,
                      itemBuilder: (context, index) {
                        final poll = _polls[index];
                        final totalVotes = poll.options.fold<int>(
                          0,
                          (sum, o) => sum + o.votes,
                        );
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
                                  GestureDetector(
                                    onTap: () => _editPoll(index),
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
                              ...List.generate(poll.options.length, (i) {
                                final option = poll.options[i];
                                final ratio = totalVotes == 0
                                    ? 0.0
                                    : option.votes / totalVotes;
                                final selected = poll.votedIndex == i;
                                return Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: GestureDetector(
                                    onTap: () => _vote(poll, i),
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
                                                      .withValues(alpha: 0.18),
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
                                                  '${option.votes}',
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
                                '$totalVotes ${tr('group_votes_suffix')}',
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
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
            Icon(Icons.how_to_vote_rounded, color: context.colors.muted, size: 44),
            const SizedBox(height: 16),
            Text(
              tr('group_empty_polls_title'),
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('group_empty_polls_subtitle'),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tr('group_new_poll_button'),
                        style: const TextStyle(
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
