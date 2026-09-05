import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

const _sections = <(String, String)>[
  (
    '1. Acceptance of Terms',
    'By creating an account or using TravelPlanner, you agree to these '
        'Terms of Service. If you do not agree, please do not use the app.',
  ),
  (
    '2. Use of the App',
    'TravelPlanner helps you plan trips, discover destinations, and '
        'coordinate travel with others. You agree to use the app only for '
        'lawful purposes and not to misuse any feature — including the '
        'Community, Group Travel, or messaging tools — to harass, spam, or '
        'mislead other users.',
  ),
  (
    '3. Your Account',
    'You are responsible for the accuracy of the information you provide '
        '(such as your profile, trip details, and expenses) and for keeping '
        'your login credentials secure. You may enable email two-factor '
        'authentication in Settings for extra protection.',
  ),
  (
    '4. Third-Party Information',
    'Weather forecasts, transport routes and fares, maps, and points of '
        'interest are sourced from third-party providers and may be '
        'incomplete, delayed, or inaccurate. Always verify critical travel '
        'details (such as transport schedules or emergency numbers) '
        'independently before relying on them.',
  ),
  (
    '5. User-Generated Content',
    'Reviews, photos, comments, and posts you submit in the Community '
        'module are your own responsibility. Content that is public may be '
        'seen by other users. Do not post anything you do not have the '
        'right to share.',
  ),
  (
    '6. Group Travel & Shared Data',
    'When you join a trip or group, trip-mates may see information you '
        'share within that group (such as itinerary items, expenses, and '
        'chat messages). Leaving a group does not retroactively remove '
        'content you already shared with it.',
  ),
  (
    '7. Limitation of Liability',
    'TravelPlanner is provided "as is" for planning assistance. We are not '
        'liable for travel disruptions, financial loss, or any decisions '
        'made based on information in the app.',
  ),
  (
    '8. Changes to These Terms',
    'We may update these Terms from time to time. Continued use of the app '
        'after changes take effect means you accept the updated Terms.',
  ),
  (
    '9. Contact',
    'Questions about these Terms can be sent through Settings → Help '
        'Center → Contact Support.',
  ),
];

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: tr('auth_terms_of_service')),
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
