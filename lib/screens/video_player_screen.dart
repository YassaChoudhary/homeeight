import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Full-screen player for a listing's walkthrough video.
class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final String title;

  const VideoPlayerScreen({super.key, required this.url, this.title = ''});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _video =
      VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
    // Platform view: avoids a black picture (sound only) on devices and
    // emulators where the default texture path fails under Impeller.
    viewType: VideoViewType.platformView,
  );
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _video
        ..setLooping(true)
        ..play();
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
    _video.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video.removeListener(_tick);
    _video.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_video.value.isInitialized) return;
    _video.value.isPlaying ? _video.pause() : _video.play();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _failed
                  ? Text("Couldn't play this video.",
                      style: AppTextStyles.body(color: Colors.white70))
                  : !v.isInitialized
                      ? const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white))
                      : GestureDetector(
                          onTap: _toggle,
                          child: AspectRatio(
                            aspectRatio: v.aspectRatio,
                            child: VideoPlayer(_video),
                          ),
                        ),
            ),
            if (v.isInitialized && !v.isPlaying)
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 44),
                  ),
                ),
              ),
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            if (v.isInitialized)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: VideoProgressIndicator(
                  _video,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: AppColors.primary,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
