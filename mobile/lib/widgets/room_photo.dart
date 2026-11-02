import 'package:flutter/material.dart';

/// A room photo from the internet, with a spinner while it loads
/// and a plain picture if it cannot load.
class RoomPhoto extends StatelessWidget {
  final String? url;
  final double? height;
  final BoxFit fit;

  const RoomPhoto({super.key, required this.url, this.height, this.fit = BoxFit.cover});

  Widget _placeholder(BuildContext context, IconData icon) {
    return Container(
      height: height,
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = url;
    if (photo == null) return _placeholder(context, Icons.hotel);

    return Image.network(
      photo,
      height: height,
      width: double.infinity,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          height: height,
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
      errorBuilder: (context, error, stack) => _placeholder(context, Icons.broken_image_outlined),
    );
  }
}
