import 'package:flutter/material.dart';

/// A neutral Material surface for feature content that needs a shared panel
/// treatment without knowing anything about the feature's domain entities.
class PromptPanel extends StatelessWidget {
  const PromptPanel({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return Card(child: content);
  }
}
