Duration parseGoogleDuration(String? raw) {
  if (raw == null || raw.isEmpty || !raw.endsWith('s')) return Duration.zero;
  final seconds = int.tryParse(raw.substring(0, raw.length - 1)) ?? 0;
  return Duration(seconds: seconds);
}
