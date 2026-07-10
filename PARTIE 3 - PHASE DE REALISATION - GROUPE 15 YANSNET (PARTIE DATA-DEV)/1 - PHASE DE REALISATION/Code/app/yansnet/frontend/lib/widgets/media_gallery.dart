// lib/widgets/media_gallery.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:dio/dio.dart';
import 'package:universal_html/html.dart' as html;
import '../utils/constants.dart';
import '../utils/media_utils.dart';

// ============================================================
// WIDGET : Miniature vidéo réelle (VideoThumbnailWidget)
// ============================================================
class VideoThumbnailWidget extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  const VideoThumbnailWidget({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  String? _thumbnailPath;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    try {
      final fullUrl = widget.url.startsWith('http')
          ? widget.url
          : '${AppConstants.baseUrl}${widget.url}';

      final tempDir = await getTemporaryDirectory();
      final videoFileName = 'thumb_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final videoFile = File('${tempDir.path}/$videoFileName');

      final response = await http.get(Uri.parse(fullUrl));
      if (response.statusCode != 200) throw Exception('Téléchargement échoué');
      await videoFile.writeAsBytes(response.bodyBytes);

      final uint8list = await VideoThumbnail.thumbnailData(
        video: videoFile.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 75,
      );
      if (uint8list == null) throw Exception('Génération miniature échouée');

      final thumbFile = File('${tempDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await thumbFile.writeAsBytes(uint8list);

      await videoFile.delete();

      if (mounted) {
        setState(() {
          _thumbnailPath = thumbFile.path;
          _loading = false;
        });
      }
    } catch (e) {
      print('❌ Erreur génération miniature : $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: Colors.grey[900],
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_error || _thumbnailPath == null) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.white70, size: 48),
              SizedBox(height: 8),
              Text('Miniature indisponible', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }
    return Image.file(
      File(_thumbnailPath!),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}

// ============================================================
// WIDGET : Lecteur vidéo local (VideoWidget)
// ============================================================
class VideoWidget extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;

  const VideoWidget({super.key, required this.url, this.width, this.height});

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final fullUrl = widget.url.startsWith('http')
          ? widget.url
          : '${AppConstants.baseUrl}${widget.url}';

      final response = await http.get(Uri.parse(fullUrl));
      if (response.statusCode != 200) throw Exception('Téléchargement échoué');

      final tempDir = await getTemporaryDirectory();
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      final controller = VideoPlayerController.file(file);
      await controller.initialize();

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isLoading = false;
        _isPlaying = true;
      });
      controller.play();
    } catch (e) {
      print('❌ Erreur vidéo : $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _togglePlay() {
    if (_controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_hasError || _controller == null) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.white70, size: 48),
              SizedBox(height: 8),
              Text('Vidéo non disponible', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
            if (!_controller!.value.isPlaying)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  size: 64,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MEDIA GALLERY (Carrousel + Fullscreen)
// ============================================================
class MediaGallery extends StatefulWidget {
  final List<String> mediaUrls;
  final List<String> mediaTypes;

  const MediaGallery({
    super.key,
    required this.mediaUrls,
    required this.mediaTypes,
  });

  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  late PageController _pageController;
  int _currentIndex = 0;
  late List<String> _effectiveMediaTypes;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _computeEffectiveTypes();
  }

  void _computeEffectiveTypes() {
    // Si mediaTypes est vide ou ne correspond pas au nombre d'URLs, on détecte automatiquement
    if (widget.mediaTypes.isEmpty || widget.mediaTypes.length != widget.mediaUrls.length) {
      _effectiveMediaTypes = widget.mediaUrls.map((url) => MediaUtils.detectType(url)).toList();
    } else {
      _effectiveMediaTypes = widget.mediaTypes;
    }
  }

  @override
  void didUpdateWidget(covariant MediaGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mediaUrls != oldWidget.mediaUrls || widget.mediaTypes != oldWidget.mediaTypes) {
      _computeEffectiveTypes();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openFullScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenMediaViewer(
          mediaUrls: widget.mediaUrls,
          mediaTypes: _effectiveMediaTypes, // ✅ utilisation de _effectiveMediaTypes
          initialIndex: _currentIndex,
        ),
      ),
    );
  }

  void _goPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goNext() {
    if (_currentIndex < widget.mediaUrls.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _downloadCurrentMedia() async {
    final url = '${AppConstants.baseUrl}${widget.mediaUrls[_currentIndex]}';
    if (kIsWeb) {
      try {
        final anchor = html.document.createElement('a') as html.AnchorElement;
        anchor.href = url;
        anchor.download = 'yansnet_${DateTime.now().millisecondsSinceEpoch}.jpg';
        anchor.click();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Téléchargement démarré'), backgroundColor: Colors.green),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } else {
      try {
        final response = await Dio().get(url, options: Options(responseType: ResponseType.bytes));
        final appDocDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = url.split('.').last.split('?').first;
        final file = File('${appDocDir.path}/yansnet_$timestamp.$extension');
        await file.writeAsBytes(response.data);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Téléchargé: ${file.path.split('/').last}'), backgroundColor: Colors.green),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.mediaUrls.length;
    if (count == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 280,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemCount: count,
                  itemBuilder: (context, index) {
                    final isVideo = _effectiveMediaTypes[index] == 'video';
                    final url = '${AppConstants.baseUrl}${widget.mediaUrls[index]}';

                    return GestureDetector(
                      onTap: _openFullScreen,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (!isVideo)
                            Image.network(
                              url,
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, progress) =>
                                  progress == null ? child : Container(
                                color: Colors.grey[200],
                                child: const Center(child: CircularProgressIndicator()),
                              ),
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                              ),
                            )
                          else
                            Stack(
                              fit: StackFit.expand,
                              children: [
                                VideoThumbnailWidget(url: url),
                                const Center(
                                  child: Icon(Icons.play_circle_filled, size: 60, color: Colors.white),
                                ),
                              ],
                            ),
                          // Bouton téléchargement
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: _downloadCurrentMedia,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(Icons.download, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            if (count > 1)
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _goPrevious,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
            if (count > 1)
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _goNext,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_right, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (count > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(count, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentIndex == index ? 20 : 8,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentIndex == index ? const Color(0xFF9E1B22) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
      ],
    );
  }
}

// ============================================================
// FULLSCREEN MEDIA VIEWER
// ============================================================
class FullScreenMediaViewer extends StatefulWidget {
  final List<String> mediaUrls;
  final List<String> mediaTypes;
  final int initialIndex;

  const FullScreenMediaViewer({
    super.key,
    required this.mediaUrls,
    required this.mediaTypes,
    required this.initialIndex,
  });

  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  late PageController _pageController;
  int _currentIndex = 0;
  late List<String> _effectiveMediaTypes;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _computeEffectiveTypes();
  }

  void _computeEffectiveTypes() {
    if (widget.mediaTypes.isEmpty || widget.mediaTypes.length != widget.mediaUrls.length) {
      _effectiveMediaTypes = widget.mediaUrls.map((url) => MediaUtils.detectType(url)).toList();
    } else {
      _effectiveMediaTypes = widget.mediaTypes;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _goPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goNext() {
    if (_currentIndex < widget.mediaUrls.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _downloadCurrentMedia() async {
    final url = '${AppConstants.baseUrl}${widget.mediaUrls[_currentIndex]}';
    if (kIsWeb) {
      try {
        final anchor = html.document.createElement('a') as html.AnchorElement;
        anchor.href = url;
        anchor.download = 'yansnet_${DateTime.now().millisecondsSinceEpoch}.jpg';
        anchor.click();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Téléchargement démarré'), backgroundColor: Colors.green),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } else {
      try {
        final response = await Dio().get(url, options: Options(responseType: ResponseType.bytes));
        final appDocDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = url.split('.').last.split('?').first;
        final file = File('${appDocDir.path}/yansnet_$timestamp.$extension');
        await file.writeAsBytes(response.data);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Téléchargé: ${file.path.split('/').last}'), backgroundColor: Colors.green),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1} / ${widget.mediaUrls.length}',
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: _downloadCurrentMedia,
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: widget.mediaUrls.length,
            itemBuilder: (context, index) {
              final isVideo = _effectiveMediaTypes[index] == 'video';
              final url = '${AppConstants.baseUrl}${widget.mediaUrls[index]}';

              if (isVideo) {
                return Center(
                  child: VideoWidget(url: url),
                );
              }

              return PhotoViewGallery.builder(
                scrollPhysics: const BouncingScrollPhysics(),
                builder: (BuildContext context, int i) {
                  return PhotoViewGalleryPageOptions(
                    imageProvider: NetworkImage(url),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2,
                    heroAttributes: PhotoViewHeroAttributes(tag: url),
                  );
                },
                itemCount: 1,
                loadingBuilder: (context, event) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              );
            },
          ),
          if (widget.mediaUrls.length > 1 && _currentIndex > 0)
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _goPrevious,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_left, color: Colors.white, size: 40),
                  ),
                ),
              ),
            ),
          if (widget.mediaUrls.length > 1 && _currentIndex < widget.mediaUrls.length - 1)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _goNext,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_right, color: Colors.white, size: 40),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}