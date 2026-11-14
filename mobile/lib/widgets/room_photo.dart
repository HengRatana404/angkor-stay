import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A room photo from the internet, with a smooth loader while it loads
/// and a luxury placeholder if it cannot load.
class RoomPhoto extends StatelessWidget {
  final String? url;
  final double? height;
  final BoxFit fit;

  const RoomPhoto({
    super.key,
    required this.url,
    this.height,
    this.fit = BoxFit.cover,
  });

  Widget _placeholder(BuildContext context, IconData icon) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C221B), Color(0xFF1E1712)],
        ),
      ),
      child: Center(child: Icon(icon, size: 40, color: angkorGold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = url;
    if (photo == null) return _placeholder(context, Icons.hotel_outlined);

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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2C221B), Color(0xFF1E1712)],
            ),
          ),
          alignment: Alignment.center,
          child: const SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: angkorGold,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) =>
          _placeholder(context, Icons.broken_image_outlined),
    );
  }
}
