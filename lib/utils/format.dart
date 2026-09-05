library;

String formatDuration(Duration d) {
  final totalMinutes = d.inMinutes;
  if (totalMinutes < 60) return '$totalMinutes min';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}min';
}

String formatDistanceMeters(int meters) {
  if (meters < 1000) return '$meters m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
}

String formatClockTime(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}
