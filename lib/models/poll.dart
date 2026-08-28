/// One option within a [Poll], with its live vote tally.
class PollOptionData {
  const PollOptionData({
    required this.id,
    required this.label,
    required this.position,
    required this.voteCount,
  });

  final String id;
  final String label;
  final int position;
  final int voteCount;
}

/// A group decision-making poll, backed by `polls` + `poll_options` +
/// `poll_votes`. [votedOptionId] is the current user's own vote, if any.
class Poll {
  const Poll({
    required this.id,
    required this.tripId,
    required this.question,
    required this.createdBy,
    required this.createdAt,
    required this.options,
    required this.votedOptionId,
  });

  final String id;
  final String tripId;
  final String question;
  final String createdBy;
  final DateTime createdAt;
  final List<PollOptionData> options;
  final String? votedOptionId;

  int get totalVotes => options.fold(0, (sum, o) => sum + o.voteCount);
}
