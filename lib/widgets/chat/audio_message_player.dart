import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Inline voice-message playback row for a chat bubble: play/pause, a
/// scrub slider, and "0:03 / 0:12". [knownDuration] — the length
/// recorded alongside the message — fills the total in immediately,
/// before the player itself has loaded enough of the file to report it.
class AudioMessagePlayer extends StatefulWidget {
  const AudioMessagePlayer({
    super.key,
    required this.url,
    required this.mine,
    this.knownDuration,
  });

  final String url;
  final bool mine;
  final Duration? knownDuration;

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _duration = widget.knownDuration;
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.url));
    }
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine ? Colors.white : context.colors.ink;
    final total = _duration ?? Duration.zero;
    final totalMs = total.inMilliseconds;
    final shownTime = _state == PlayerState.playing || _position > Duration.zero
        ? _position
        : total;

    return SizedBox(
      width: 200,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _toggle,
            icon: Icon(
              _state == PlayerState.playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: fg,
              size: 30,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: fg,
                inactiveTrackColor: fg.withValues(alpha: 0.3),
                thumbColor: fg,
              ),
              child: Slider(
                value: totalMs == 0
                    ? 0
                    : _position.inMilliseconds.clamp(0, totalMs).toDouble(),
                max: totalMs == 0 ? 1 : totalMs.toDouble(),
                onChanged: totalMs == 0
                    ? null
                    : (v) => _player.seek(Duration(milliseconds: v.round())),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _format(shownTime),
            style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}
