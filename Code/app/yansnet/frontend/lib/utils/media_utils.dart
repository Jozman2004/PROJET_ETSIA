class MediaUtils {
  static bool isVideo(String url) {
    final ext = url.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
  }

  static bool isImage(String url) => !isVideo(url);

  static String detectType(String url) {
    return isVideo(url) ? 'video' : 'photo';
  }
}