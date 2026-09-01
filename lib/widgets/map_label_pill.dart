import 'package:flutter/material.dart';

/// Small white label chip overlaid on the app's stylized map surfaces,
/// e.g. "Tap pins to select" or "You are here · Komtar, George Town".
class MapLabelPill extends StatelessWidget {
  const MapLabelPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0B1D3A),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
