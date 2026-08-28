import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// UI-only translator with a common travel-phrases reference and a
/// dummy free-text translate box.
class TranslatorScreen extends StatefulWidget {
  const TranslatorScreen({super.key});

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  final _controller = TextEditingController();
  String _translated = '';

  static final _phrases = [
    (en: 'Hello', ms: 'Helo'),
    (en: 'Thank you', ms: 'Terima kasih'),
    (en: 'How much is this?', ms: 'Berapa harga ini?'),
    (en: 'Where is the toilet?', ms: 'Di mana tandas?'),
    (en: 'Delicious!', ms: 'Sedap!'),
    (en: 'Excuse me', ms: 'Maafkan saya'),
    (en: 'I need help', ms: 'Saya perlukan bantuan'),
    (en: 'Goodbye', ms: 'Selamat tinggal'),
  ];

  void _translate() {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    final match = _phrases.where(
      (p) => p.en.toLowerCase() == input.toLowerCase(),
    );
    setState(() {
      _translated = match.isNotEmpty
          ? match.first.ms
          : '"$input" (translation preview)';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Translator',
              subtitle: 'English → Bahasa Malaysia',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.ink.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _controller,
                          maxLines: 2,
                          style: TextStyle(color: context.colors.ink),
                          decoration: InputDecoration(
                            hintText: 'Type in English…',
                            hintStyle: TextStyle(color: context.colors.muted),
                            border: InputBorder.none,
                            suffixIcon: IconButton(
                              onPressed: _translate,
                              icon: Icon(
                                Icons.translate_rounded,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                        if (_translated.isNotEmpty) ...[
                          Divider(height: 24),
                          Text(
                            _translated,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Common Phrases',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 14),
                  ..._phrases.map(
                    (p) => Container(
                      margin: EdgeInsets.only(bottom: 10),
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.colors.card,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.ink.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.en,
                                  style: TextStyle(
                                    color: context.colors.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  p.ms,
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.volume_up_rounded,
                            color: context.colors.muted,
                            size: 19,
                          ),
                        ],
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
