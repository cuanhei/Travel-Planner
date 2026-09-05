class LoginActivityEntry {
  const LoginActivityEntry({
    required this.id,
    required this.signedInAt,
    this.deviceInfo,
  });

  final String id;
  final DateTime signedInAt;
  final String? deviceInfo;

  factory LoginActivityEntry.fromRow(Map<String, dynamic> row) {
    return LoginActivityEntry(
      id: row['id'] as String,
      signedInAt: DateTime.parse(row['signed_in_at'] as String).toLocal(),
      deviceInfo: row['device_info'] as String?,
    );
  }
}
