// lib/widgets/mention_text.dart
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Widget pour afficher un texte contenant des mentions (@username) avec mise en surbrillance.
/// Les mentions sont cliquables pour déclencher une action (ex: navigation vers le profil).
class MentionText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final void Function(String username)? onMentionTap;

  const MentionText({
    super.key,
    required this.text,
    this.style,
    this.onMentionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<TextSpan> spans = [];
    final RegExp mentionRegex = RegExp(r'@\w+');
    int lastMatchEnd = 0;

    // Parcourir toutes les occurrences de mentions
    for (final match in mentionRegex.allMatches(text)) {
      // Texte avant la mention
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: style,
        ));
      }

      // La mention (ex: @username)
      final String mention = match.group(0)!;
      final String username = mention.substring(1); // sans le @

      spans.add(TextSpan(
        text: mention,
        style: (style ?? const TextStyle()).copyWith(
          color: const Color(0xFF9E1B22), // Couleur rouge YANSNET
          fontWeight: FontWeight.w600,
        ),
        recognizer: onMentionTap != null
            ? (TapGestureRecognizer()
              ..onTap = () => onMentionTap!(username))
            : null,
      ));

      lastMatchEnd = match.end;
    }

    // Reste du texte après la dernière mention
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: style,
      ));
    }

    return RichText(
      text: TextSpan(
        style: style ?? const TextStyle(fontSize: 14, color: Colors.black87),
        children: spans,
      ),
    );
  }
}