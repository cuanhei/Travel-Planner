import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/list_tile_card.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: tr('auth_about')),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: AppColors.horizon,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.horizon.last.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.travel_explore_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'TravelPlanner',
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tr('auth_version_prefix')} 1.0.0',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      tr('auth_about_description'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ListTileCard(
                    icon: Icons.description_outlined,
                    title: tr('auth_terms_of_service'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TermsOfServiceScreen(),
                      ),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.privacy_tip_outlined,
                    title: tr('auth_privacy_policy'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      tr('auth_made_with_flutter'),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
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
