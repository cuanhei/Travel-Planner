import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

const _sections = <(String, String)>[
  (
    '1. Information We Collect',
    'We collect the information you provide directly — your name, email, '
        'phone number, date of birth, gender, nationality, address, bio, '
        'and profile photo — plus the trips, expenses, saved places, and '
        'reviews you create while using the app.',
  ),
  (
    '2. How We Use Your Information',
    'Your information is used to run core features: building your '
        'itineraries, showing weather and transport relevant to your trips, '
        'splitting group expenses, and displaying your profile to other '
        'travelers.',
  ),
  (
    '3. Public Profile & Visibility',
    'Settings → Privacy & Security lets you switch your profile between '
        'Public (other users can see your full profile details) and '
        'Private (other users only see your name, photo, and bio). '
        'Trip-mates in a shared group can always see information relevant '
        'to that trip, regardless of this setting.',
  ),
  (
    '4. Data Storage & Security',
    'Your data is stored using Supabase, with row-level security rules '
        'restricting who can read or edit each record. Optional email '
        'two-factor authentication is available in Settings for added '
        'account security.',
  ),
  (
    '5. Sharing With Third Parties',
    'We do not sell your personal information. Limited data is sent to '
        'third-party services strictly to provide app features — for '
        'example, destination coordinates sent to weather and transport '
        'route providers.',
  ),
  (
    '6. Your Choices',
    'You can edit or remove most profile fields at any time from Edit '
        'Profile, and control who sees your details via the Public Profile '
        'switch. Account deletion and data export are shown in Settings for '
        'demonstration purposes in this version of the app.',
  ),
  (
    '7. Children\'s Privacy',
    'TravelPlanner is not directed at children under 13, and we do not '
        'knowingly collect personal information from them.',
  ),
  (
    '8. Changes to This Policy',
    'We may update this Privacy Policy as the app evolves. Continued use '
        'of the app after an update means you accept the revised policy.',
  ),
  (
    '9. Contact',
    'Questions about this Privacy Policy can be sent through Settings → '
        'Help Center → Contact Support.',
  ),
];

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: tr('auth_privacy_policy')),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(
                    'Last updated: January 2026',
                    style: TextStyle(color: context.colors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  for (final (heading, body) in _sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heading,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            body,
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
