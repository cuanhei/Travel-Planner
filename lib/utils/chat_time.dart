const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Sep 2, 3:45 PM" — a chat message's sent time, or (in Group Chat)
/// its seen time. Shared by Group Chat and Direct Message screens.
String formatChatDateTime(DateTime utc) {
  final d = utc.toLocal();
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '${_monthNames[d.month - 1]} ${d.day}, $hour12:$minute $period';
}
