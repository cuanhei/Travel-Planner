import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../services/translation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// Free-text translator (via [TranslationService]'s live API call) with a
/// from/to language picker, plus a common travel-phrases reference.
class TranslatorScreen extends StatefulWidget {
  const TranslatorScreen({super.key});

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  final _service = TranslationService();
  final _controller = TextEditingController();
  final _tts = FlutterTts();
  String _translated = '';
  bool _translating = false;
  String? _error;

  String _fromLang = 'en';
  String _toLang = 'ms';
  List<TranslateLanguage> _languages = const [];

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

  @override
  void initState() {
    super.initState();
    _service.fetchLanguages().then((languages) {
      if (mounted) setState(() => _languages = languages);
    });
  }

  /// The picker list's display name for [code] — falls back to the raw
  /// code if [_languages] hasn't loaded yet.
  String _nameFor(String code) {
    for (final language in _languages) {
      if (language.code == code) return language.name;
    }
    return code == 'auto' ? 'Detect language' : code;
  }

  Future<void> _translate() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _translating) return;
    setState(() {
      _translating = true;
      _error = null;
    });
    try {
      final result = await _service.translate(
        input,
        from: _fromLang,
        to: _toLang,
      );
      if (!mounted) return;
      setState(() {
        _translated = result;
        _translating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not translate: $e';
        _translating = false;
      });
    }
  }

  void _swapDirection() {
    if (_fromLang == 'auto') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text("Pick a specific \"from\" language first to swap."),
        ),
      );
      return;
    }
    setState(() {
      final previousFrom = _fromLang;
      _fromLang = _toLang;
      _toLang = previousFrom;
      _translated = '';
      _error = null;
    });
  }

  Future<void> _pickLanguage({required bool isFrom}) async {
    final languages = _languages;
    if (languages.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _LanguagePickerSheet(
        languages: languages,
        includeDetect: isFrom,
        selected: isFrom ? _fromLang : _toLang,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _fromLang = picked;
      } else {
        _toLang = picked;
      }
      _translated = '';
      _error = null;
    });
  }

  /// Reads [text] aloud in Bahasa Malaysia via the device's text-to-speech
  /// engine, for a "Common Phrases" entry — [languageCode] defaults to
  /// `'ms-MY'` since every phrase's second column is Malay. Fails
  /// silently into a snackbar rather than a crash if the device has no
  /// Malay voice installed (common on devices without that language pack).
  Future<void> _speak(String text, {String languageCode = 'ms-MY'}) async {
    try {
      await _tts.stop();
      await _tts.setLanguage(languageCode);
      await _tts.speak(text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not read this phrase aloud: $e'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Translator',
              subtitle: 'Translate between any two languages',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _LanguagePill(
                      label: _nameFor(_fromLang),
                      onTap: () => _pickLanguage(isFrom: true),
                    ),
                  ),
                  IconButton(
                    onPressed: _swapDirection,
                    icon: Icon(Icons.swap_horiz_rounded, color: AppColors.accent),
                  ),
                  Expanded(
                    child: _LanguagePill(
                      label: _nameFor(_toLang),
                      onTap: () => _pickLanguage(isFrom: false),
                    ),
                  ),
                ],
              ),
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
                          onSubmitted: (_) => _translate(),
                          style: TextStyle(color: context.colors.ink),
                          decoration: InputDecoration(
                            hintText: 'Type in ${_nameFor(_fromLang)}…',
                            hintStyle: TextStyle(color: context.colors.muted),
                            border: InputBorder.none,
                            suffixIcon: _translating
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    onPressed: _translate,
                                    icon: Icon(
                                      Icons.translate_rounded,
                                      color: AppColors.accent,
                                    ),
                                  ),
                          ),
                        ),
                        if (_error != null) ...[
                          Divider(height: 24),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFE0554B),
                              fontSize: 13,
                            ),
                          ),
                        ] else if (_translated.isNotEmpty) ...[
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
                          IconButton(
                            onPressed: () => _speak(p.ms),
                            icon: Icon(
                              Icons.volume_up_rounded,
                              color: context.colors.muted,
                              size: 19,
                            ),
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

/// Tappable pill showing the currently picked language, opening
/// [_LanguagePickerSheet] when tapped.
class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: context.colors.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable bottom sheet listing every language [TranslationService]
/// supports, for picking either side of a translation. Pops with the
/// chosen language code.
class _LanguagePickerSheet extends StatefulWidget {
  const _LanguagePickerSheet({
    required this.languages,
    required this.includeDetect,
    required this.selected,
  });

  final List<TranslateLanguage> languages;

  /// Whether to show "Detect language" (`auto`) at the top — only
  /// meaningful for the "from" side; Lingva doesn't support `auto` as a
  /// translation target.
  final bool includeDetect;
  final String selected;

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.languages
        .where((l) => l.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a language',
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(color: context.colors.ink),
                decoration: InputDecoration(
                  hintText: 'Search languages…',
                  hintStyle: TextStyle(color: context.colors.muted),
                  prefixIcon: Icon(Icons.search_rounded, color: context.colors.muted),
                  filled: true,
                  fillColor: context.colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (widget.includeDetect && _query.isEmpty)
                      _LanguageTile(
                        name: 'Detect language',
                        selected: widget.selected == 'auto',
                        onTap: () => Navigator.of(context).pop('auto'),
                      ),
                    for (final language in filtered)
                      _LanguageTile(
                        name: language.name,
                        selected: widget.selected == language.code,
                        onTap: () => Navigator.of(context).pop(language.code),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(
        name,
        style: TextStyle(
          color: context.colors.ink,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: AppColors.accent)
          : null,
    );
  }
}
