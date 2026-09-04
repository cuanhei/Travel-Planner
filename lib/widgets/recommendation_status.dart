import 'package:flutter/material.dart';

/// A failed search is distinct from a successful search with no feasible stops.
class RecommendationStatus extends StatelessWidget {
  const RecommendationStatus({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry nearby places'),
          ),
      ],
    ),
  );
}
