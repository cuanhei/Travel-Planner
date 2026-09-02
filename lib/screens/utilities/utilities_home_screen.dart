import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/list_tile_card.dart';
import 'currency_converter_screen.dart';
import 'emergency_contacts_screen.dart';
import 'packing_list_screen.dart';
import 'translator_screen.dart';

/// Hub linking into the trip utility tools: packing list, currency
/// converter, translator, and emergency contacts.
class UtilitiesHomeScreen extends StatelessWidget {
  const UtilitiesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Trip Utilities',
              subtitle: 'Handy tools for your trip',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  ListTileCard(
                    icon: Icons.checklist_rounded,
                    title: 'Packing List',
                    subtitle: 'Auto-generated checklist',
                    iconColor: Color(0xFF11998E),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PackingListScreen()),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.currency_exchange_rounded,
                    title: 'Currency Converter',
                    subtitle: 'Exchange rates',
                    iconColor: Color(0xFFFFB347),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CurrencyConverterScreen(),
                      ),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.translate_rounded,
                    title: 'Translator',
                    subtitle: 'Common travel phrases',
                    iconColor: Color(0xFF5C6BC0),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TranslatorScreen()),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.emergency_rounded,
                    title: 'Emergency Contacts',
                    subtitle: 'Local emergency information',
                    iconColor: Colors.redAccent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EmergencyContactsScreen(),
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
