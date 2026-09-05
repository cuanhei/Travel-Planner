import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../services/translation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// Free-text translator (via [TranslationService]'s live API call) with a
/// from/to language picker, plus a common travel-phrases reference that's
/// translated into the same from/to pair — see [_translatePhrases].
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

  /// Canonical set of common travel phrases, in English — translated live
  /// into whichever languages [_fromLang]/[_toLang] are currently set to
  /// (see [_translatePhrases]), so changing the language pair above
  /// changes what's shown here too, instead of this staying fixed to a
  /// hardcoded English → Malay pair.
  static const _phrasesEn = [
    'Hello',
    'Thank you',
    'How much is this?',
    'Where is the toilet?',
    'Delicious!',
    'Excuse me',
    'I need help',
    'Goodbye',
  ];

  /// [_phrasesEn] translated into [_fromLang]/[_toLang] — parallel lists,
  /// same index order as [_phrasesEn]. `null` until the first translation
  /// batch finishes; the *previous* pair's results are otherwise kept
  /// visible while a new batch is in flight, rather than blanking the
  /// section on every language change.
  List<String>? _phrasesFrom;
  List<String>? _phrasesTo;
  bool _phrasesLoading = false;
  String? _phrasesError;

  /// Lingva's ISO 639-1 codes aren't always what a device's TTS engine
  /// expects (e.g. plain `'ms'` vs the `'ms-MY'` locale tag) — this covers
  /// the languages most relevant to a Malaysia travel app; anything else
  /// falls back to the bare code, which some engines accept fine anyway
  /// (and [_speak]'s error handling already covers voices that don't).
  static const _ttsLocales = {
    'en': 'en-US',
    'ms': 'ms-MY',
    'zh': 'zh-CN',
    'ta': 'ta-IN',
    'hi': 'hi-IN',
    'id': 'id-ID',
    'th': 'th-TH',
    'vi': 'vi-VN',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'ar': 'ar-SA',
    'fr': 'fr-FR',
    'de': 'de-DE',
    'es': 'es-ES',
    'pt': 'pt-PT',
    'ru': 'ru-RU',
  };

  @override
  void initState() {
    super.initState();
    _service.fetchLanguages().then((languages) {
      if (mounted) setState(() => _languages = languages);
    });
    _translatePhrases();
  }

  /// Translates every entry in [_phrasesEn] into [_fromLang] and [_toLang]
  /// — skipping the live call for whichever side is already English (or
  /// "Detect language", which isn't a real target), since that's the
  /// phrases' own source text. Called on load and after every language
  /// change.
  Future<void> _translatePhrases() async {
    setState(() {
      _phrasesLoading = true;
      _phrasesError = null;
    });
    try {
      final from = _fromLang == 'en' || _fromLang == 'auto'
          ? _phrasesEn
          : await Future.wait(
              _phrasesEn.map(
                (p) => _service.translate(p, from: 'en', to: _fromLang),
              ),
            );
      final to = _toLang == 'en'
          ? _phrasesEn
          : await Future.wait(
              _phrasesEn.map(
                (p) => _service.translate(p, from: 'en', to: _toLang),
              ),
            );
      if (!mounted) return;
      setState(() {
        _phrasesFrom = from;
        _phrasesTo = to;
        _phrasesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phrasesError = 'Could not translate common phrases: $e';
        _phrasesLoading = false;
      });
    }
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
    _translatePhrases();
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
    _translatePhrases();
  }

  /// Reads [text] aloud via the device's text-to-speech engine, in
  /// [langCode]'s language (a Lingva code like `'ms'`, mapped to a TTS
  /// locale tag via [_ttsLocales]) — for a "Common Phrases" entry, always
  /// [_toLang], so it matches whatever's actually shown there. Fails
  /// silently into a snackbar rather than a crash if the device has no
  /// voice installed for that language.
  Future<void> _speak(String text, String langCode) async {
    try {
      await _tts.stop();
      await _tts.setLanguage(_ttsLocales[langCode] ?? langCode);
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
                    icon: Icon(
                      Icons.swap_horiz_rounded,
                      color: AppColors.accent,
                    ),
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
                  Row(
                    children: [
                      Text(
                        'Common Phrases',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (_phrasesLoading) ...[
                        SizedBox(width: 8),
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 14),
                  if (_phrasesError != null)
                    Text(
                      _phrasesError!,
                      style: const TextStyle(
                        color: Color(0xFFE0554B),
                        fontSize: 13,
                      ),
                    )
                  else if (_phrasesFrom == null || _phrasesTo == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    for (var i = 0; i < _phrasesEn.length; i++)
                      Container(
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
                                    _phrasesFrom![i],
                                    style: TextStyle(
                                      color: context.colors.ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    _phrasesTo![i],
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
                              onPressed: () => _speak(_phrasesTo![i], _toLang),
                              icon: Icon(
                                Icons.volume_up_rounded,
                                color: context.colors.muted,
                                size: 19,
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
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: context.colors.muted,
                  ),
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
