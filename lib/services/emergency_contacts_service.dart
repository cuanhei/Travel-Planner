import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip_stop_location.dart';
import 'photon_service.dart';

/// A single emergency service entry — a label, a dialable number, and the
/// icon/color the Emergency Contacts screen renders it with.
typedef EmergencyContact = ({
  String label,
  String number,
  IconData icon,
  Color color,
});

/// [EmergencyContactsService.contactsForState]'s result: the numbers to
/// show and the state they're for. [hasStateSpecificNumbers] is false
/// when [stateLabel] has no curated entries beyond the national three
/// (see [EmergencyContactsService] for why that's not treated as an
/// error — the national numbers are still fully correct everywhere).
class ResolvedEmergencyContacts {
  const ResolvedEmergencyContacts({
    required this.stateLabel,
    required this.contacts,
    required this.hasStateSpecificNumbers,
  });

  final String stateLabel;
  final List<EmergencyContact> contacts;
  final bool hasStateSpecificNumbers;
}

/// Police/Ambulance/Fire (Bomba) numbers per Malaysian state, keyed to
/// wherever a trip's stop actually is — each stop's saved coordinates are
/// reverse-geocoded (via [PhotonService], the same one Weather uses) to a
/// state, so which numbers the Emergency Contacts screen shows follows
/// the traveler's itinerary (George Town → Penang's numbers, Alor Setar →
/// Kedah's, etc.) rather than a live GPS fix.
///
/// Police/Ambulance/Fire are the same nationwide (999/999/994) — what
/// actually varies by state is facility-specific numbers like the local
/// Tourist Police desk or the state's main hospital. This only has
/// verified real numbers for Penang so far ([_stateExtras]); every other
/// state just shows the correct national three rather than a
/// plausible-looking but unverified number.
class EmergencyContactsService {
  EmergencyContactsService({PhotonService? photonService})
    : _photon = photonService ?? PhotonService();

  final PhotonService _photon;

  static const _nationalContacts = <EmergencyContact>[
    (
      label: 'Police',
      number: '999',
      icon: Icons.local_police_rounded,
      color: Color(0xFF5C6BC0),
    ),
    (
      label: 'Ambulance',
      number: '999',
      icon: Icons.local_hospital_rounded,
      color: Colors.redAccent,
    ),
    (
      label: 'Fire Department (Bomba)',
      number: '994',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFFB347),
    ),
  ];

  /// Verified, state-specific numbers beyond the national three — kept
  /// deliberately small rather than inventing plausible-looking numbers
  /// for states this hasn't actually verified.
  static const _stateExtras = <String, List<EmergencyContact>>{
    'Penang': [
      (
        label: 'Tourist Police (Penang)',
        number: '03-2149 6590',
        icon: Icons.shield_rounded,
        color: Color(0xFF11998E),
      ),
      (
        label: 'Penang Hospital',
        number: '04-222 5333',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
  };

  /// Maps Photon/OSM's state name — often the Malay official form, e.g.
  /// "Pulau Pinang" — to the display name used in [_stateExtras] and
  /// shown in the UI.
  static const _stateNameAliases = {
    'Pulau Pinang': 'Penang',
    'W.P. Kuala Lumpur': 'Kuala Lumpur',
    'Wilayah Persekutuan Kuala Lumpur': 'Kuala Lumpur',
    'Wilayah Persekutuan Labuan': 'Labuan',
    'Wilayah Persekutuan Putrajaya': 'Putrajaya',
    'Melaka': 'Malacca',
  };

  /// Reverse-geocodes [stop]'s saved coordinates to its Malaysian state
  /// name (e.g. "Penang", "Kedah"), or null if that fails or the point
  /// has no resolvable state.
  Future<String?> stateForStop(TripStopLocation stop) async {
    try {
      final area = await _photon.reverseAdministrative(
        LatLng(stop.latitude, stop.longitude),
      );
      final rawState = area?.state;
      if (rawState == null) return null;
      return _stateNameAliases[rawState] ?? rawState;
    } catch (_) {
      return null;
    }
  }

  /// Emergency contacts for [stateLabel] (as returned by [stateForStop])
  /// — always the national three, plus any verified extras for that
  /// state. `null`/unrecognized states just get the national three.
  ResolvedEmergencyContacts contactsForState(String? stateLabel) {
    final extras = stateLabel != null ? _stateExtras[stateLabel] : null;
    return ResolvedEmergencyContacts(
      stateLabel: stateLabel ?? 'your location',
      contacts: [..._nationalContacts, ...?extras],
      hasStateSpecificNumbers: extras != null,
    );
  }
}
