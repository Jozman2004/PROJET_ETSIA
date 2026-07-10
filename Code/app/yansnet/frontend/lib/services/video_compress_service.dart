import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:path_provider/path_provider.dart';

class VideoCompressService {
  static final VideoCompressService _instance = VideoCompressService._internal();
  factory VideoCompressService() => _instance;
  VideoCompressService._internal();

  /// Compresse une vidéo avec une qualité donnée (0-100) et une largeur max.
  /// Retourne le chemin du fichier compressé.
  Future<File?> compressVideo(
    String inputPath, {
    int quality = 70,
    int? maxWidth,
    int? maxHeight,
    bool keepAspectRatio = true,
  }) async {
    try {
      final info = await VideoCompress.compressVideo(
        inputPath,
        quality: quality,
        deleteOrigin: false, // Garder l'original
        includeAudio: true,
        frameRate: 30,
        maxWidth: maxWidth ?? 720,
        maxHeight: maxHeight ?? 1280,
        minWidth: 320,
        minHeight: 320,
        // Ces paramètres fonctionnent avec video_compress ^3.1.0+
      );
      if (info != null && info.file != null) {
        return File(info.file!.path);
      }
      return null;
    } catch (e) {
      print('❌ Erreur compression vidéo: $e');
      // En cas d'échec, retourner le fichier original
      return File(inputPath);
    }
  }

  /// Récupère la taille du fichier en Mo
  static double getFileSizeInMB(String path) {
    final file = File(path);
    if (!file.existsSync()) return 0;
    return file.lengthSync() / (1024 * 1024);
  }

  /// Récupère les métadonnées de la vidéo
  static Future<MediaInfo?> getVideoInfo(String path) async {
    try {
      final info = await VideoCompress.getMediaInfo(path);
      return info;
    } catch (e) {
      print('❌ Erreur récupération infos vidéo: $e');
      return null;
    }
  }
}