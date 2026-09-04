import 'package:flutter/material.dart';

import '../screens/search_destination_screen.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Tappable search bar that opens [SearchDestinationScreen] — shared by
/// the Home dashboard and the Explore tab so both start the same
/// destination search flow.
class DestinationSearchBar extends StatelessWidget {
  const DestinationSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => SearchDestinationScreen())),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: context.colors.muted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('home_search_destinations_hint'),
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
