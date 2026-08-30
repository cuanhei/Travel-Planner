import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/coming_soon.dart';
import '../../widgets/detail_header.dart';

/// Local emergency numbers and embassy contacts for the trip destination.
class EmergencyContactsScreen extends StatelessWidget {
  const EmergencyContactsScreen({super.key});

  static final _contacts = [
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
      label: 'Fire Department',
      number: '994',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFFB347),
    ),
    (
      label: 'Tourist Police',
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
    (
      label: 'Your Embassy',
      number: '03-2170 2200',
      icon: Icons.account_balance_rounded,
      color: AppColors.accent,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Emergency Contacts',
              subtitle: 'Local numbers for Penang, Malaysia',
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                itemCount: _contacts.length,
                itemBuilder: (context, index) {
                  final c = _contacts[index];
                  return Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.ink.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: c.color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(c.icon, color: c.color, size: 22),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.label,
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                c.number,
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: Color(0xFF11998E).withValues(alpha: 0.12),
                          shape: CircleBorder(),
                          child: InkWell(
                            customBorder: CircleBorder(),
                            onTap: () =>
                                showComingSoon(context, 'Calling ${c.label}'),
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.call_rounded,
                                color: Color(0xFF11998E),
                                size: 18,
                              ),
                            ),
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
