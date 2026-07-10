import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/constants.dart';

class FullScreenVideoViewer extends StatefulWidget {
  final String fileUrl;
  final String? fileName;

  const FullScreenVideoViewer({
    super.key,
    required this.fileUrl,
    this.fileName,
  });

  @override
  State<FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<FullScreenVideoViewer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  double _currentPosition = 0.0;
  double _duration = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final fullUrl = widget.fileUrl.startsWith('http')
        ? widget.fileUrl
        : '${AppConstants.baseUrl}${widget.fileUrl}';
    _controller = VideoPlayerController.networkUrl(Uri.parse(fullUrl));
    _controller.addListener(_onControllerUpdate);
    await _controller.initialize();
    _duration = _controller.value.duration?.inMilliseconds?.toDouble() ?? 0;
    setState(() {
      _isInitialized = true;
      _isPlaying = true;
    });
    _controller.play();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    if (_controller.value.isBuffering != _isBuffering) {
      setState(() => _isBuffering = _controller.value.isBuffering);
    }
    if (!_isDragging) {
      final pos = _controller.value.position.inMilliseconds.toDouble();
      final dur = _controller.value.duration?.inMilliseconds.toDouble() ?? 0;
      setState(() {
        _currentPosition = pos;
        _duration = dur;
      });
    }
  }

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  void _onSeek(double value) {
    setState(() {
      _isDragging = true;
      _currentPosition = value;
    });
  }

  void _onSeekComplete(double value) {
    setState(() {
      _isDragging = false;
      _currentPosition = value;
    });
    final duration = _controller.value.duration;
    if (duration != null) {
      final position = duration * (value / 100);
      _controller.seekTo(position);
    }
  }

  String _formatTime(double milliseconds) {
    if (milliseconds <= 0) return '00:00';
    final totalSec = (milliseconds / 1000).floor();
    final min = (totalSec ~/ 60).toString().padLeft(2, '0');
    final sec = (totalSec % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  Future<void> _downloadVideo() async {
    final fullUrl = widget.fileUrl.startsWith('http')
        ? widget.fileUrl
        : '${AppConstants.baseUrl}${widget.fileUrl}';
    try {
      // Demander la permission de stockage
      if (await Permission.storage.request().isGranted ||
          await Permission.manageExternalStorage.request().isGranted) {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = widget.fileName ?? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final savePath = '${appDir.path}/$fileName';
        await Dio().download(fullUrl, savePath);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Vidéo téléchargée : $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission de stockage refusée'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur téléchargement: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
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
          widget.fileName ?? 'Vidéo',
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: _downloadVideo,
          ),
        ],
      ),
      body: Center(
        child: _isInitialized
            ? GestureDetector(
                onTap: _togglePlay,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Vidéo
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(_controller),
                            if (_isBuffering)
                              const CircularProgressIndicator(color: Colors.white),
                            if (!_isPlaying && !_isBuffering)
                              Container(
                                width: 60,
                                height: 60,
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  size: 36,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Contrôles
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: Colors.black87,
                      child: Column(
                        children: [
                          // Curseur
                          Row(
                            children: [
                              Text(
                                _formatTime(_currentPosition),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              Expanded(
                                child: Slider(
                                  value: _duration > 0
                                      ? (_currentPosition / _duration) * 100
                                      : 0,
                                  min: 0,
                                  max: 100,
                                  activeColor: Colors.green,
                                  inactiveColor: Colors.grey,
                                  onChanged: _onSeek,
                                  onChangeEnd: _onSeekComplete,
                                ),
                              ),
                              Text(
                                _formatTime(_duration),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                          // Boutons lecture / pause / avance / recul
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.replay_10, color: Colors.white),
                                onPressed: () {
                                  final newPos = _controller.value.position - const Duration(seconds: 10);
                                  if (newPos.inMilliseconds < 0) {
                                    _controller.seekTo(Duration.zero);
                                  } else {
                                    _controller.seekTo(newPos);
                                  }
                                },
                              ),
                              const SizedBox(width: 20),
                              IconButton(
                                icon: Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 36,
                                ),
                                onPressed: _togglePlay,
                              ),
                              const SizedBox(width: 20),
                              IconButton(
                                icon: const Icon(Icons.forward_10, color: Colors.white),
                                onPressed: () {
                                  final duration = _controller.value.duration;
                                  if (duration != null) {
                                    final newPos = _controller.value.position + const Duration(seconds: 10);
                                    if (newPos > duration) {
                                      _controller.seekTo(duration);
                                    } else {
                                      _controller.seekTo(newPos);
                                    }
                                  }
                                },
                              ),
                              const SizedBox(width: 30),
                              IconButton(
                                icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : const Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}