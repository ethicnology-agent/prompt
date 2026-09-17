import 'package:flutter/material.dart';

/// A stable, local identity mark. Never downloads a profile image or discloses
/// the identifier to a third-party avatar service.
class IdentityAvatar extends StatelessWidget {
  const IdentityAvatar({required this.identifier, this.size = 60, super.key});

  final String identifier;
  final double size;

  @override
  Widget build(BuildContext context) {
    var hash = 0;
    for (final unit in identifier.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final hue = (hash % 360).toDouble();
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HSLColor.fromAHSL(1, hue, .65, .82).toColor(),
              HSLColor.fromAHSL(1, (hue + 60) % 360, .5, .43).toColor(),
            ],
          ),
        ),
        child: SizedBox.square(
          dimension: size,
          child: Icon(
            Icons.terminal_rounded,
            size: size * .42,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
