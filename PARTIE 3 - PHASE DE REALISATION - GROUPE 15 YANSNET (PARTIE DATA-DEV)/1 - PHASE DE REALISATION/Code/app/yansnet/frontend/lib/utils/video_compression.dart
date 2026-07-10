// lib/utils/video_compression.dart
import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:cross_file/cross_file.dart';

class VideoCompressionService {
  static Future<XFile?> compressVideo({
    required XFile videoFile,
    int targetSizeMB = 20,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final originalSize = await videoFile.length();
      final originalSizeMB = originalSize / (1024 * 1024);

      // Si la vidéo est déjà sous la taille cible, on renvoie l'original
      if (originalSizeMB <= targetSizeMB) {
        return videoFile;
      }

      // Qualités disponibles (Low, Medium, Default)
      final qualities = [
        VideoQuality.LowQuality,
        VideoQuality.MediumQuality,
        VideoQuality.DefaultQuality,
      ];

      XFile? bestResult;
      int bestSize = originalSize ~/ 2;

      for (int i = 0; i < qualities.length; i++) {
        final quality = qualities[i];
        if (onProgress != null) {
          onProgress((i + 1) / qualities.length);
        }

        final mediaInfo = await VideoCompress.compressVideo(
          videoFile.path,
          quality: quality,
        );

        if (mediaInfo == null || mediaInfo.path == null) continue;

        final compressedFile = File(mediaInfo.path!);
        final size = await compressedFile.length();
        final sizeMB = size / (1024 * 1024);

        // Si la taille est déjà inférieure à la cible, on retourne ce fichier
        if (sizeMB <= targetSizeMB) {
          return XFile(compressedFile.path);
        }

        // Sinon, on garde la meilleure compression (la plus petite)
        if (size < bestSize) {
          bestSize = size;
          bestResult = XFile(compressedFile.path);
        }
      }

      // Si aucune compression n'a atteint la cible, on renvoie la meilleure trouvée
      return bestResult ?? videoFile;
    } catch (e) {
      print('Erreur compression vidéo: $e');
      return videoFile; // fallback
    }
  }

  static Future<void> deleteCompressedFile(XFile? file) async {
    if (file == null) return;
    try {
      final f = File(file.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}