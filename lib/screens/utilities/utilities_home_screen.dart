import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/list_tile_card.dart';
import 'currency_converter_screen.dart';
import 'emergency_contacts_screen.dart';
import 'packing_list_screen.dart';
import 'translator_screen.dart';

class UtilitiesHomeScreen extends StatelessWidget {
  const UtilitiesHomeScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('utilities_home_title'),
              subtitle: tr('utilities_home_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  ListTileCard(
                    icon: Icons.checklist_rounded,
                    title: tr('utilities_packing_list_title'),
                    subtitle: tr('utilities_packing_list_card_subtitle'),
                    iconColor: Color(0xFF11998E),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PackingListScreen(tripId: tripId),
                      ),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.currency_exchange_rounded,
                    title: tr('utilities_currency_converter_title'),
                    subtitle: tr('utilities_currency_converter_card_subtitle'),
                    iconColor: Color(0xFFFFB347),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CurrencyConverterScreen(),
                      ),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.translate_rounded,
                    title: tr('utilities_translator_title'),
                    subtitle: tr('utilities_translator_card_subtitle'),
                    iconColor: Color(0xFF5C6BC0),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TranslatorScreen()),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.emergency_rounded,
                    title: tr('utilities_emergency_contacts_title'),
                    subtitle: tr('utilities_emergency_contacts_card_subtitle'),
                    iconColor: Colors.redAccent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EmergencyContactsScreen(tripId: tripId),
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
