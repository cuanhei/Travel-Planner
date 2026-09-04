import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

final _urlPattern = RegExp(r'(https?://\S+)');

/// Opens [url] in the platform browser (or the associated app, e.g. a
/// `mailto:`/`tel:` link) via `url_launcher`.
Future<void> openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// A [Text.rich] that finds `http(s)://` URLs anywhere inside [text] and
/// makes just that substring tappable — opening it via [openLink] — while
/// the rest renders as plain text in [style]. Unlike wrapping the whole
/// widget in a `GestureDetector` (which can only react to taps on the full
/// widget, not a portion of running text), this uses a `TapGestureRecognizer`
/// per link span, so a caption/comment/link can mix plain words and URLs.
class LinkifiedText extends StatelessWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle,
    this.onTapLink,
  });

  final String text;
  final TextStyle? style;

  /// Style applied to the tappable link portion; defaults to [style] with
  /// an underline and the current theme's accent color.
  final TextStyle? linkStyle;

  /// Called with the tapped URL instead of [openLink] when set — e.g. to
  /// navigate to an in-app screen for links that point back into this app,
  /// falling back to opening external links normally.
  final ValueChanged<String>? onTapLink;

  @override
  Widget build(BuildContext context) {
    final matches = _urlPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: style);
    }

    final resolvedLinkStyle =
        linkStyle ??
        (style ?? const TextStyle()).copyWith(
          color: AppColors.accent,
          decoration: TextDecoration.underline,
        );

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: resolvedLinkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => (onTapLink ?? openLink)(url),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(TextSpan(style: style, children: spans));
  }
}
