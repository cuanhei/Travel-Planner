import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip_stop_location.dart';
import 'photon_service.dart';

typedef EmergencyContact = ({
  String label,
  String number,
  IconData icon,
  Color color,
});

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

  static const _stateExtras = <String, List<EmergencyContact>>{
    'Penang': [
      (
        label: 'Tourist Police (Penang)',
        number: '03-2149 6590',
        icon: Icons.shield_rounded,
        color: Color(0xFF11998E),
      ),
      (
        label: 'Penang Police HQ (IPK)',
        number: '04-269 1999',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Penang Fire & Rescue HQ',
        number: '04-386 6010',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Penang Hospital',
        number: '04-222 5333',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Selangor': [
      (
        label: 'Selangor Police HQ (IPK)',
        number: '03-5514 5222',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Selangor Fire & Rescue HQ',
        number: '03-7846 4444',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Selangor Hospital (Shah Alam)',
        number: '03-5526 3000',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Johor': [
      (
        label: 'Johor Police HQ (IPK)',
        number: '07-221 2999',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Johor Fire & Rescue HQ',
        number: '07-340 9999',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Johor Hospital (Sultanah Aminah, JB)',
        number: '07-225 7000',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Kedah': [
      (
        label: 'Kedah Police HQ (IPK)',
        number: '04-739 3999',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Kedah Fire & Rescue HQ',
        number: '04-733 3444',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Kedah Hospital (Sultanah Bahiyah)',
        number: '04-740 6233',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Kelantan': [
      (
        label: 'Kelantan Police HQ (IPK)',
        number: '09-745 0999',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Kelantan Fire & Rescue (Kota Bharu)',
        number: '09-748 4444',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Kelantan Hospital (Raja Perempuan Zainab II)',
        number: '09-745 2000',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Malacca': [
      (
        label: 'Malacca Police HQ (IPK)',
        number: '06-285 1999',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Malacca Fire & Rescue (Melaka Tengah)',
        number: '06-231 6844',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Malacca Hospital',
        number: '06-289 2344',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Negeri Sembilan': [
      (
        label: 'Negeri Sembilan Police HQ (IPK)',
        number: '06-768 2417',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Negeri Sembilan Fire & Rescue HQ',
        number: '06-767 7089',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: "Negeri Sembilan Hospital (Tuanku Ja'afar)",
        number: '06-768 4000',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Pahang': [
      (
        label: 'Pahang Police HQ (IPK)',
        number: '09-505 2222',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Pahang Fire & Rescue HQ',
        number: '09-570 5999',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Pahang Hospital (Tengku Ampuan Afzan)',
        number: '09-513 3333',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Perak': [
      (
        label: 'Perak Police HQ (IPK)',
        number: '05-240 1999',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Perak Fire & Rescue (Ipoh Zone 1)',
        number: '05-547 4444',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Perak Hospital (Raja Permaisuri Bainun)',
        number: '05-208 5000',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Perlis': [
      (
        label: 'Perlis Police HQ (IPK)',
        number: '04-987 2417',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Perlis Fire & Rescue (Kangar)',
        number: '04-976 0544',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Perlis Hospital (Tuanku Fauziah)',
        number: '04-973 8000',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Sabah': [
      (
        label: 'Sabah Police HQ (IPK)',
        number: '088-454 738',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Sabah Fire & Rescue HQ',
        number: '088-210 214',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Sabah Hospital (Queen Elizabeth)',
        number: '088-517 555',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Sarawak': [
      (
        label: 'Sarawak Police HQ (IPK)',
        number: '082-240 800',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Sarawak Fire & Rescue HQ',
        number: '082-365 994',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Sarawak Hospital (Umum Sarawak)',
        number: '082-276 666',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Terengganu': [
      (
        label: 'Terengganu Police HQ (IPK)',
        number: '09-635 4745',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Terengganu Fire & Rescue HQ',
        number: '09-622 4444',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Terengganu Hospital (Sultanah Nur Zahirah)',
        number: '09-621 2121',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Kuala Lumpur': [
      (
        label: 'Kuala Lumpur Police HQ (IPK)',
        number: '03-2146 0585',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Kuala Lumpur Fire & Rescue (Jalan Hang Tuah)',
        number: '03-9221 7222',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Kuala Lumpur Hospital',
        number: '03-2615 5555',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Labuan': [
      (
        label: 'Labuan District Police HQ (IPD)',
        number: '087-412 222',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Labuan Fire & Rescue (Central)',
        number: '087-414 444',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Labuan Hospital',
        number: '087-596 888',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
    'Putrajaya': [
      (
        label: 'Putrajaya District Police HQ (IPD)',
        number: '03-8886 2222',
        icon: Icons.local_police_rounded,
        color: Color(0xFF5C6BC0),
      ),
      (
        label: 'Fire & Rescue Dept. National HQ (Putrajaya)',
        number: '03-8892 7600',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFFB347),
      ),
      (
        label: 'Putrajaya Hospital',
        number: '03-8312 4200',
        icon: Icons.medical_services_rounded,
        color: Colors.redAccent,
      ),
    ],
  };

  static const _stateNameAliases = {
    'Pulau Pinang': 'Penang',
    'W.P. Kuala Lumpur': 'Kuala Lumpur',
    'Wilayah Persekutuan Kuala Lumpur': 'Kuala Lumpur',
    'Wilayah Persekutuan Labuan': 'Labuan',
    'Wilayah Persekutuan Putrajaya': 'Putrajaya',
    'Melaka': 'Malacca',
  };

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

  ResolvedEmergencyContacts contactsForState(String? stateLabel) {
    final extras = stateLabel != null ? _stateExtras[stateLabel] : null;
    return ResolvedEmergencyContacts(
      stateLabel: stateLabel ?? 'your location',
      contacts: [..._nationalContacts, ...?extras],
      hasStateSpecificNumbers: extras != null,
    );
  }
}
