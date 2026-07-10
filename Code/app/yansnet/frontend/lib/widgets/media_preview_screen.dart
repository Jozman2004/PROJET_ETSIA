// lib/widgets/media_preview_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import 'package:video_player/video_player.dart';
import '../utils/video_compression.dart';

class MediaPreviewScreen extends StatefulWidget {
  final List<XFile> initialFiles;
  final Future<void> Function(List<XFile> files, String caption) onSend;

  const MediaPreviewScreen({
    super.key,
    required this.initialFiles,
    required this.onSend,
  });

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  List<XFile> _files = [];
  final TextEditingController _captionController = TextEditingController();
  bool _isSending = false;
  double _compressionProgress = 0.0;
  bool _compressing = false;

  @override
  void initState() {
    super.initState();
    _files = widget.initialFiles;
  }

  void _removeFile(int index) {
    setState(() {
      _files.removeAt(index);
    });
  }

  Future<void> _send() async {
    if (_files.isEmpty || _isSending) return;
    setState(() => _isSending = true);

    // Compresser les vidéos si nécessaire
    List<XFile> compressedFiles = [];
    _compressing = true;
    for (int i = 0; i < _files.length; i++) {
      final file = _files[i];
      final ext = file.name.split('.').last.toLowerCase();
      final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
      if (isVideo) {
        setState(() => _compressionProgress = 0.0);
        final compressed = await VideoCompressionService.compressVideo(
          videoFile: file,
          targetSizeMB: 20,
          onProgress: (p) {
            setState(() => _compressionProgress = p);
          },
        );
        if (compressed != null) {
          compressedFiles.add(compressed);
        } else {
          // Si la compression échoue, on garde l'original
          compressedFiles.add(file);
        }
      } else {
        compressedFiles.add(file);
      }
    }
    _compressing = false;

    final caption = _captionController.text.trim();
    await widget.onSend(compressedFiles, caption);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_files.length} média(s)'),
        backgroundColor: const Color(0xFF9E1B22),
        foregroundColor: Colors.white,
        actions: [
          if (_files.isNotEmpty)
            TextButton(
              onPressed: _isSending ? null : _send,
              child: Text(
                _isSending ? 'Envoi...' : 'Envoyer',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final file = _files[index];
                final ext = file.name.split('.').last.toLowerCase();
                final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
                final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);

                return Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[200],
                        image: isImage
                            ? DecorationImage(
                                image: FileImage(File(file.path)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: isVideo
                          ? Center(
                              child: Icon(Icons.play_circle_filled, size: 40, color: Colors.white),
                            )
                          : null,
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removeFile(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    if (isVideo)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('🎬', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (_compressing)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _compressionProgress),
                  const SizedBox(height: 8),
                  Text('Compression : ${(_compressionProgress * 100).toInt()}%'),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _captionController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Ajouter un message (optionnel)...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}