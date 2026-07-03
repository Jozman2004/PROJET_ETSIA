import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../services/api_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  List<XFile> _selectedMedia = []; // Liste des médias sélectionnés
  bool _loading = false;
  final _api = ApiService();
  final _picker = ImagePicker();

  /// Ajoute des images (multi-sélection)
  Future<void> _pickImages() async {
    final List<XFile>? results = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 1080);
    if (results != null && results.isNotEmpty) {
      setState(() {
        _selectedMedia.addAll(results);
      });
    }
  }

  /// Ajoute une vidéo (une seule à la fois)
  Future<void> _pickVideo() async {
    final XFile? result = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2));
    if (result != null) {
      // Vérification taille (uniquement sur desktop)
      if (!kIsWeb) {
        final file = File(result.path);
        final size = await file.length();
        const limit = 20 * 1024 * 1024; // 20 Mo
        if (size > limit) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vidéo trop lourde. Max 20 Mo'), backgroundColor: Colors.red),
          );
          return;
        }
      }
      setState(() {
        _selectedMedia.add(result);
      });
    }
  }

  /// Supprime un média de la liste
  void _removeMedia(int index) {
    setState(() {
      _selectedMedia.removeAt(index);
    });
  }

  Future<void> _publish() async {
    if (_contentCtrl.text.trim().isEmpty && _selectedMedia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoutez du texte ou au moins un média'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final List<String> filePaths = _selectedMedia.map((xfile) => xfile.path).toList();
      await _api.createPost(
        content: _contentCtrl.text.trim().isEmpty ? null : _contentCtrl.text.trim(),
        tags: _tagsCtrl.text.trim().isEmpty ? null : _tagsCtrl.text.trim(),
        filePaths: filePaths, // envoi de plusieurs fichiers
        isInstitutional: false,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      print('❌ Erreur publication : $e');
      String msg = 'Publication impossible';
      if (e is DioException) {
        msg = e.response?.data?['error'] ?? e.message;
      } else {
        msg = e.toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: const Text('Nouvelle publication', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _loading ? null : _publish,
            child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9E1B22)))
                : const Text('Publier', style: TextStyle(color: Color(0xFF9E1B22), fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _contentCtrl,
              maxLines: 5,
              maxLength: 500,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Que souhaitez-vous partager avec le campus ?',
                border: InputBorder.none,
                counterStyle: TextStyle(color: Colors.grey),
              ),
            ),
            TextField(
              controller: _tagsCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.tag, color: Colors.grey),
                hintText: 'Tags : info, sport, evenement...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
            const SizedBox(height: 16),
            // Zone d'aperçu des médias sélectionnés (grille)
            if (_selectedMedia.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  childAspectRatio: 1.0,
                ),
                itemCount: _selectedMedia.length,
                itemBuilder: (context, index) {
                  final media = _selectedMedia[index];
                  final isVideo = media.path.toLowerCase().contains('.mp4') ||
                      media.path.toLowerCase().contains('.mov') ||
                      media.path.toLowerCase().contains('.avi');
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      isVideo
                          ? Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.videocam, size: 40, color: Colors.grey),
                            )
                          : (kIsWeb
                              ? Image.network(media.path, fit: BoxFit.cover)
                              : Image.file(File(media.path), fit: BoxFit.cover)),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeMedia(index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                      if (isVideo)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                            child: const Text('🎥', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                    ],
                  );
                },
              )
            else
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  width: double.infinity,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text('Ajouter des images', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // Boutons d'ajout de médias supplémentaires
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _toolBtn(Icons.photo_library, 'Images', _pickImages),
                _toolBtn(Icons.videocam_outlined, 'Vidéo', _pickVideo, color: const Color(0xFF006838)),
                _toolBtn(Icons.camera_alt_outlined, 'Caméra', () async {
                  final img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
                  if (img != null) setState(() => _selectedMedia.add(img));
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final c = color ?? const Color(0xFF9E1B22);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: c, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}