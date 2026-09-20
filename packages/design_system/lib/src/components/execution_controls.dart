import 'package:flutter/material.dart';

import 'app_button.dart';

/// One entry point on roomy desktop layouts, detailed controls elsewhere.
class ExecutionControls extends StatelessWidget {
  const ExecutionControls({
    required this.compact,
    required this.summary,
    required this.onOpen,
    super.key,
  });

  final Widget compact;
  final String summary;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = MediaQuery.sizeOf(context);
      if (onOpen == null ||
          constraints.maxWidth < 560 ||
          size.width < 1200 ||
          size.height < 600 ||
          MediaQuery.textScalerOf(context).scale(14) > 18) {
        return compact;
      }
      return Row(
        children: [
          AppIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Execution settings',
            onPressed: onOpen,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Semantics(
              container: true,
              label: 'Current execution settings',
              value: summary,
              excludeSemantics: true,
              child: Tooltip(
                message: summary,
                excludeFromSemantics: true,
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
