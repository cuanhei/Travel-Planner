import 'dart:async';

import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';

class CodeExpiryTimer extends StatefulWidget {
  const CodeExpiryTimer({
    super.key,
    this.duration = const Duration(seconds: 60),
    required this.resetKey,
    this.onExpired,
  });

  final Duration duration;
  final Object resetKey;
  final VoidCallback? onExpired;

  @override
  State<CodeExpiryTimer> createState() => _CodeExpiryTimerState();
}

class _CodeExpiryTimerState extends State<CodeExpiryTimer> {
  late Duration _remaining = widget.duration;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant CodeExpiryTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) _start();
  }

  void _start() {
    _timer?.cancel();
    setState(() => _remaining = widget.duration);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _remaining - const Duration(seconds: 1);
      setState(() => _remaining = next.isNegative ? Duration.zero : next);
      if (_remaining == Duration.zero) {
        _timer?.cancel();
        widget.onExpired?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining == Duration.zero;
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    final countdown = '$minutes:${seconds.toString().padLeft(2, '0')}';
    return Text(
      expired
          ? tr('auth_code_expired')
          : '${tr('auth_code_expires_in')}$countdown',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: expired ? Colors.redAccent : context.colors.muted,
        fontWeight: expired ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12.5,
      ),
    );
  }
}
