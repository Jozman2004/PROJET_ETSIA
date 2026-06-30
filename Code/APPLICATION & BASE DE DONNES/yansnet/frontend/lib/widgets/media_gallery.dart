import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:html' as html;
import '../utils/constants.dart';

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
  int _currentIndex = 0;

  void _openFullScreen(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenMediaViewer(
          mediaUrls: widget.mediaUrls,
          mediaTypes: widget.mediaTypes,
          initialIndex: index,
        ),
      ),
    );
  }

  Future<void> _downloadMedia(int index) async {
    final url = '${AppConstants.baseUrl}${widget.mediaUrls[index]}';
    
    if (kIsWeb) {
      try {
        final anchor = html.document.createElement('a') as html.AnchorElement;
        anchor.href = url;
        anchor.download = 'yansnet_${DateTime.now().millisecondsSinceEpoch}.jpg';
        anchor.click();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Téléchargement démarré'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } else {
      try {
        final response = await Dio().get(url, options: Options(responseType: ResponseType.bytes));
        final appDocDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = url.split('.').last.split('?').first;
        final file = File('${appDocDir.path}/yansnet_$timestamp.$extension');
        await file.writeAsBytes(response.data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Image téléchargée: ${file.path.split('/').last}'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _goPrevious() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _openFullScreen(_currentIndex);
    }
  }

  void _goNext() {
    if (_currentIndex < widget.mediaUrls.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _openFullScreen(_currentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.mediaUrls.length;
    
    if (count == 0) return const SizedBox.shrink();
    if (count == 1) return _buildSingleMedia(0);
    if (count == 2) return _buildTwoMedia();
    if (count == 3) return _buildThreeMedia();
    return _buildGridMedia();
  }

  Widget _buildSingleMedia(int index) {
    final isVideo = widget.mediaTypes[index] == 'video';
    return GestureDetector(
      onTap: () => _openFullScreen(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Image.network(
              '${AppConstants.baseUrl}${widget.mediaUrls[index]}',
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, loadingProgress) =>
                  loadingProgress == null ? child : Container(
                    height: 300,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              errorBuilder: (_, __, ___) => Container(
                height: 300,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, size: 50),
              ),
            ),
            if (isVideo)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: Icon(Icons.play_circle_filled, size: 60, color: Colors.white),
                ),
              ),
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _downloadMedia(index),
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
      ),
    );
  }

  Widget _buildTwoMedia() {
    return Row(
      children: [
        Expanded(child: _buildMediaItem(0, 250)),
        const SizedBox(width: 4),
        Expanded(child: _buildMediaItem(1, 250)),
      ],
    );
  }

  Widget _buildThreeMedia() {
    return Row(
      children: [
        Expanded(flex: 2, child: _buildMediaItem(0, 250)),
        const SizedBox(width: 4),
        Expanded(
          flex: 1,
          child: Column(
            children: [
              _buildMediaItem(1, 122),
              const SizedBox(height: 4),
              _buildMediaItem(2, 122),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridMedia() {
    final remaining = widget.mediaUrls.length - 4;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 4,
      mainAxisSpacing: 4,
      childAspectRatio: 1,
      children: List.generate(4, (index) {
        final isLast = index == 3 && remaining > 0;
        return GestureDetector(
          onTap: () => _openFullScreen(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  '${AppConstants.baseUrl}${widget.mediaUrls[index]}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image)),
                ),
                if (widget.mediaTypes[index] == 'video')
                  const Center(child: Icon(Icons.play_circle_filled, size: 40, color: Colors.white)),
                if (isLast)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Text(
                        '+$remaining',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildMediaItem(int index, double height) {
    final isVideo = widget.mediaTypes[index] == 'video';
    return GestureDetector(
      onTap: () => _openFullScreen(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Image.network(
              '${AppConstants.baseUrl}${widget.mediaUrls[index]}',
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: height,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image),
              ),
            ),
            if (isVideo)
              Center(
                child: Icon(Icons.play_circle_filled, size: 40, color: Colors.white),
              ),
            Positioned(
              bottom: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _downloadMedia(index),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.download, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// FULL SCREEN MEDIA VIEWER AVEC FLÈCHES
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
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _initVideoPlayer();
  }

  void _initVideoPlayer() {
    final currentMediaType = widget.mediaTypes[_currentIndex];
    if (currentMediaType == 'video') {
      final videoUrl = '${AppConstants.baseUrl}${widget.mediaUrls[_currentIndex]}';
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _videoController!.initialize().then((_) {
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _videoController?.dispose();
      _videoController = null;
      _isVideoPlaying = false;
      _initVideoPlayer();
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
              final isVideo = widget.mediaTypes[index] == 'video';
              final url = '${AppConstants.baseUrl}${widget.mediaUrls[index]}';
              
              if (isVideo) {
                return _buildVideoViewer();
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
          // Flèche gauche
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
          // Flèche droite
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

  Widget _buildVideoViewer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_videoController!.value.isPlaying) {
            _videoController!.pause();
            _isVideoPlaying = false;
          } else {
            _videoController!.play();
            _isVideoPlaying = true;
          }
        });
      },
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
          if (!_isVideoPlaying)
            Center(
              child: Container(
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
            ),
        ],
      ),
    );
  }
}