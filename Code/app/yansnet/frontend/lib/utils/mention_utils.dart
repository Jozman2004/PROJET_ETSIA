// lib/utils/mention_utils.dart

class MentionUtils {
  /// Extrait la liste des usernames mentionnés (sans le @)
  static List<String> extractMentions(String text) {
    if (text.isEmpty) return [];
    final RegExp regex = RegExp(r'@(\w+)');
    final matches = regex.allMatches(text);
    return matches.map((m) => m.group(1)!).toList();
  }

  /// Remplace les mentions par des espaces réservés pour l'affichage
  static String encodeMentions(String text) {
    return text.replaceAllMapped(RegExp(r'@(\w+)'), (m) => '@${m.group(1)}');
  }

  /// Vérifie si un caractère est un séparateur valide (fin de mot)
  static bool isSeparator(String char) {
    return char == ' ' || char == '\n' || char == '\t' || char == '.' || char == ',' || char == '!' || char == '?';
  }
}