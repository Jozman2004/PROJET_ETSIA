// lib/utils/message_utils.dart
class MessageUtils {
  /// Retourne un texte lisible pour l'aperçu d'un message.
  /// Si le message est un partage de post, le texte dépend de l'expéditeur.
  static String getPreviewText(String? content, {bool isSentByMe = false}) {
    if (content == null) return '';
    if (isPostShare(content)) {
      return isSentByMe ? 'Vous avez envoyé un post' : 'Un post vous a été envoyé';
    }
    return content;
  }

  /// Vérifie si le message est un partage de post.
  /// Supporte les préfixes avec ou sans emoji (pour rétrocompatibilité).
  static bool isPostShare(String? content) {
    if (content == null) return false;
    return content.startsWith('PARTAGE:') || content.startsWith('PARTAGE:');
  }

  /// Extrait l'ID du post depuis le message de partage.
  static String? extractPostId(String? content) {
    if (content == null) return null;
    String clean = content;
    if (clean.startsWith('PARTAGE:')) {
      clean = clean.substring('PARTAGE:'.length);
    } else if (clean.startsWith('PARTAGE:')) {
      clean = clean.substring('PARTAGE:'.length);
    } else {
      return null;
    }
    final id = clean.trim();
    return id.isEmpty ? null : id;
  }
}