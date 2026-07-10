import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class VideoHelper {
  /// Télécharge une vidéo depuis une URL et retourne un [VideoPlayerController] local.
  static Future<VideoPlayerController> loadVideoFromUrl(String url) async {
    // 1. Télécharger les bytes
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Impossible de télécharger la vidéo');
    }

    // 2. Sauvegarder dans un fichier temporaire
    final tempDir = await getTemporaryDirectory();
    final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(response.bodyBytes);

    // 3. Créer un controller local
    return VideoPlayerController.file(file);
  }
}