import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

import 'specimens.dart';

void main() => runApp(const ComponentCatalog());

class ComponentCatalog extends StatelessWidget {
  const ComponentCatalog({super.key});

  @override
  Widget build(BuildContext context) => Widgetbook.material(
    home: const Center(
      child: Text('Select a component to inspect its states.'),
    ),
    lightTheme: promptTheme(),
    darkTheme: promptDarkTheme(),
    directories: [
      WidgetbookFolder(
        name: 'UI kit',
        children: [
          for (final specimen in specimens)
            WidgetbookComponent(
              name: specimen.name,
              useCases: [
                WidgetbookUseCase(
                  name: 'States',
                  builder: (_) => SpecimenPage(specimen: specimen),
                ),
              ],
            ),
        ],
      ),
    ],
    addons: [
      MaterialThemeAddon(
        themes: [
          WidgetbookTheme(name: 'Light', data: promptTheme()),
          WidgetbookTheme(name: 'Dark', data: promptDarkTheme()),
        ],
      ),
      ViewportAddon([
        const ViewportData(
          name: 'Compact',
          width: 360,
          height: 800,
          pixelRatio: 1,
          platform: TargetPlatform.android,
        ),
        const ViewportData(
          name: 'Landscape',
          width: 800,
          height: 360,
          pixelRatio: 1,
          platform: TargetPlatform.android,
        ),
        const ViewportData(
          name: 'Desktop',
          width: 1280,
          height: 800,
          pixelRatio: 1,
          platform: TargetPlatform.linux,
        ),
      ]),
      TextScaleAddon(min: 1, max: 2, initialScale: 1),
    ],
  );
}
