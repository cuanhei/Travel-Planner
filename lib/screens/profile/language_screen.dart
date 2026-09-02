import 'package:flutter/material.dart';

import '../../l10n/app_language.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/simple_card.dart';
import '../home_screen.dart';

/// Language picker: search filters the list live (no page reload — it's
/// just a local list filter), and picking a language immediately switches
/// the whole app via [currentLanguageCode]/[setAppLanguage].
///
/// Picking a language also resets navigation back to Home. Flutter skips
/// rebuilding a widget subtree when its parent passes an *identical*
/// widget instance again (e.g. this app's `static final` tab-body lists),
/// so a language change wouldn't otherwise reliably refresh every already
/// -mounted screen sitting behind this one on the stack. A full remount
/// via `pushAndRemoveUntil` sidesteps that entirely.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  final _searchController = TextEditingController();
  List<AppLanguage> _filtered = supportedLanguages;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? supportedLanguages
          : supportedLanguages
              .where(
                (l) =>
                    l.englishName.toLowerCase().contains(q) ||
                    l.nativeName.toLowerCase().contains(q) ||
                    l.code.toLowerCase().contains(q),
              )
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('auth_language_title'),
              subtitle: 'Choose your preferred language',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(color: context.colors.ink),
                decoration: InputDecoration(
                  hintText: tr('auth_search_language'),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: context.colors.muted,
                  ),
                  filled: true,
                  fillColor: context.colors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: currentLanguageCode,
                builder: (context, activeCode, _) {
                  if (_filtered.isEmpty) {
                    return Center(
                      child: Text(
                        tr('auth_no_languages_found'),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    children: _filtered.map((lang) {
                      final selected = lang.code == activeCode;
                      return SimpleCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: EdgeInsets.zero,
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              await setAppLanguage(lang.code);
                              if (!context.mounted) return;
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => HomeScreen(),
                                ),
                                (route) => false,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Text(
                                    lang.flag,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          lang.nativeName,
                                          style: TextStyle(
                                            color: context.colors.ink,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          lang.englishName,
                                          style: TextStyle(
                                            color: context.colors.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: selected
                                        ? AppColors.accent
                                        : context.colors.muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
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
