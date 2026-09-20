import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A tint and the disc it sits on.
@immutable
class AvatarColorPair {
  const AvatarColorPair(this.tint, this.background);
  final Color tint;
  final Color background;
}

/// The six pairs Happy picks between, in its order.
///
/// Taken from `AvatarBrutalist.tsx`. Keeping the list and its order identical
/// means a given session keeps the same colours in both applications, which is
/// what makes a side-by-side capture comparable at all.
const List<AvatarColorPair> avatarColorPairs = [
  AvatarColorPair(Color(0xFFFFA617), Color(0xFF0056B3)), // orange on deep blue
  AvatarColorPair(Color(0xFF59C9DF), Color(0xFFDC2626)), // cyan on bold red
  AvatarColorPair(Color(0xFFC678FF), Color(0xFF16A34A)), // purple on forest
  AvatarColorPair(Color(0xFFFF79D7), Color(0xFF047857)), // pink on teal
  AvatarColorPair(Color(0xFFFFD800), Color(0xFF4C1D95)), // yellow on purple
  AvatarColorPair(Color(0xFF84E600), Color(0xFFC026D3)), // lime on magenta
];

/// Tint used when an avatar is drawn quietly, for a session whose machine left.
const Color avatarMonochromeTint = Color(0xFF999999);

/// Disc used in the same case.
const Color avatarMonochromeBackground = Color(0xFFF0F0F0);

/// The string hash Happy seeds its avatars with.
///
/// Ported from `hashCode` in `AvatarBrutalist.tsx`:
///
/// ```js
/// hash = ((hash << 5) - hash) + char;
/// hash = hash & hash;
/// ```
///
/// The wrap-around has to be reproduced in two places, not one. JavaScript's
/// `<<` truncates to a signed 32-bit integer before the subtraction, and the
/// trailing `& hash` truncates again after it. A port that only truncates at the
/// end, or that lets the value grow past 2^31 as Dart happily would, picks a
/// different colour for the same session and quietly breaks the comparison.
int avatarHashCode(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = _toInt32(_toInt32(hash << 5) - hash + unit);
  }
  return hash.abs();
}

int _toInt32(int value) {
  final truncated = value & 0xFFFFFFFF;
  return truncated >= 0x80000000 ? truncated - 0x100000000 : truncated;
}

/// A stable, local identity mark.
///
/// Never downloads a profile image or discloses the identifier to a third-party
/// avatar service: the whole mark is derived from [identifier] on the device.
///
/// The shape of the thing matches Happy's default `brutalist` avatar — a flat
/// disc in one of [avatarColorPairs], with a geometric mark inset to 80% of the
/// diameter and painted in the pair's tint. Happy picks that mark from a library
/// of 420 bundled artworks; Prompt draws its own from the same hash, so the
/// variety and the palette line up without copying another project's artwork.
class IdentityAvatar extends StatelessWidget {
  const IdentityAvatar({
    required this.identifier,
    this.size = 60,
    this.monochrome = false,
    this.square = false,
    super.key,
  });

  final String identifier;
  final double size;

  /// Draw the mark quietly, for a session that is no longer reachable.
  final bool monochrome;

  /// Square off the disc, for a header or a tile that is not a list row.
  final bool square;

  @override
  Widget build(BuildContext context) {
    final pair =
        avatarColorPairs[avatarHashCode('${identifier}color') %
            avatarColorPairs.length];
    final background = monochrome
        ? avatarMonochromeBackground
        : pair.background;
    final tint = monochrome ? avatarMonochromeTint : pair.tint;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            shape: square ? BoxShape.rectangle : BoxShape.circle,
          ),
          child: Center(
            child: SizedBox.square(
              dimension: size * 0.8,
              child: CustomPaint(
                painter: _IdentityMarkPainter(
                  seed: avatarHashCode(identifier),
                  tint: tint,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How many distinct marks the painter can produce.
///
/// Four quadrants, each independently one of six figures, gives 1296
/// combinations before the two rotations below — comfortably more than the 420
/// artworks the reference ships, so two sessions colliding is no likelier here.
const int _figuresPerQuadrant = 6;

class _IdentityMarkPainter extends CustomPainter {
  _IdentityMarkPainter({required this.seed, required this.tint});

  final int seed;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = tint
      ..isAntiAlias = true;
    final cell = size.width / 2;
    var remaining = seed;
    for (var index = 0; index < 4; index++) {
      final figure = remaining % _figuresPerQuadrant;
      remaining = remaining ~/ _figuresPerQuadrant;
      final quarterTurns = remaining % 4;
      remaining = remaining ~/ 4;
      final origin = Offset((index % 2) * cell, (index ~/ 2) * cell);
      canvas.save();
      canvas.translate(origin.dx + cell / 2, origin.dy + cell / 2);
      canvas.rotate(quarterTurns * math.pi / 2);
      canvas.translate(-cell / 2, -cell / 2);
      _paintFigure(canvas, paint, cell, figure);
      canvas.restore();
    }
  }

  void _paintFigure(Canvas canvas, Paint paint, double cell, int figure) {
    final square = Rect.fromLTWH(0, 0, cell, cell);
    switch (figure) {
      case 0:
        canvas.drawRect(square, paint);
      case 1:
        // A quarter disc filling the corner.
        canvas.drawPath(
          Path()
            ..moveTo(0, cell)
            ..lineTo(0, 0)
            ..arcToPoint(Offset(cell, cell), radius: Radius.circular(cell))
            ..close(),
          paint,
        );
      case 2:
        canvas.drawCircle(square.center, cell * 0.38, paint);
      case 3:
        // A half filling the lower edge.
        canvas.drawRect(Rect.fromLTWH(0, cell / 2, cell, cell / 2), paint);
      case 4:
        canvas.drawPath(
          Path()
            ..moveTo(0, cell)
            ..lineTo(cell, cell)
            ..lineTo(cell, 0)
            ..close(),
          paint,
        );
      case 5:
        // A bar across the middle, the one figure that leaves both edges bare.
        canvas.drawRect(
          Rect.fromLTWH(0, cell * 0.36, cell, cell * 0.28),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_IdentityMarkPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.tint != tint;
}

class IdentityAvatarButton extends StatelessWidget {
  const IdentityAvatarButton({
    required this.identifier,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final String identifier;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: Semantics(
      label: tooltip,
      child: IdentityAvatar(identifier: identifier, size: 32),
    ),
  );
}
