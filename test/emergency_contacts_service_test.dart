import 'package:flutter_test/flutter_test.dart';
import 'package:travelplanner/models/trip_stop_location.dart';
import 'package:travelplanner/services/emergency_contacts_service.dart';

void main() {
  final service = EmergencyContactsService();

  test('George Town, Penang resolves to Penang with its extra contacts', () async {
    const stop = TripStopLocation(
      name: 'George Town',
      address: 'George Town, Penang, Malaysia',
      latitude: 5.4141,
      longitude: 100.3288,
    );

    final state = await service.stateForStop(stop);
    expect(state, 'Penang');

    final resolved = service.contactsForState(state);
    expect(resolved.stateLabel, 'Penang');
    expect(resolved.hasStateSpecificNumbers, isTrue);
    expect(resolved.contacts.map((c) => c.label), contains('Tourist Police (Penang)'));
    expect(resolved.contacts.map((c) => c.label), contains('Penang Hospital'));
  });

  test('Alor Setar, Kedah resolves to Kedah with only the national numbers', () async {
    const stop = TripStopLocation(
      name: 'Alor Setar',
      address: 'Alor Setar, Kedah, Malaysia',
      latitude: 6.1184,
      longitude: 100.3685,
    );

    final state = await service.stateForStop(stop);
    expect(state, 'Kedah');

    final resolved = service.contactsForState(state);
    expect(resolved.stateLabel, 'Kedah');
    expect(resolved.hasStateSpecificNumbers, isFalse);
    expect(resolved.contacts.length, 3);
    expect(resolved.contacts.map((c) => c.number), containsAll(['999', '994']));
  });
}
