import 'package:flutter/material.dart';

import '../screens/search_destination_screen.dart';
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
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => SearchDestinationScreen())),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: context.colors.muted, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search destinations…',
                  style: TextStyle(color: context.colors.muted, fontSize: 14.5),
                ),
              ),
              Container(
                width: 1,
                height: 22,
                color: context.colors.muted.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 12),
              Icon(Icons.tune_rounded, color: context.colors.ink, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
