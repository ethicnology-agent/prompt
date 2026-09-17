"""Deterministic package-boundary regression checks using disposable fixtures."""

import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest

from check_architecture import main


class PackageBoundaryTest(unittest.TestCase):
    def check_source(self, source, path='packages/design_system/lib/component.dart'):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                target = Path(path)
                target.parent.mkdir(parents=True)
                target.write_text(source)
                with contextlib.redirect_stdout(io.StringIO()):
                    return main()
            finally:
                os.chdir(previous)

    def test_flutter_is_allowed(self):
        self.assertEqual(self.check_source("import 'package:flutter/widgets.dart';"), 0)

    def test_application_import_is_rejected(self):
        self.assertEqual(self.check_source("import 'package:prompt/app/prompt_app.dart';"), 1)

    def test_foreign_internal_export_is_rejected(self):
        self.assertEqual(self.check_source("export 'package:other/src/secret.dart';"), 1)

    def test_network_dependency_is_rejected(self):
        self.assertEqual(self.check_source("import 'package:http/http.dart';"), 1)

    def test_relative_escape_is_rejected(self):
        self.assertEqual(self.check_source("import '../../../app/lib/secret.dart';"), 1)

    def test_platform_io_is_rejected(self):
        self.assertEqual(self.check_source("import 'dart:io';"), 1)

    def test_catalog_import_in_application_is_rejected(self):
        self.assertEqual(self.check_source("import 'package:catalog/main.dart';", 'lib/main.dart'), 1)

    def test_widgetbook_import_in_application_is_rejected(self):
        self.assertEqual(self.check_source("import 'package:widgetbook/widgetbook.dart';", 'lib/main.dart'), 1)

    def test_catalog_can_import_kit(self):
        self.assertEqual(self.check_source("import 'package:design_system/design_system.dart';", 'apps/catalog/lib/main.dart'), 0)

    def test_catalog_cannot_import_application(self):
        self.assertEqual(self.check_source("import 'package:prompt/app/prompt_app.dart';", 'apps/catalog/lib/main.dart'), 1)

    def test_new_material_button_in_feature_is_rejected(self):
        self.assertEqual(self.check_source('FilledButton(onPressed: null, child: Text("Save"));', 'lib/features/example/presentation/view.dart'), 1)

    def test_shared_button_in_feature_is_allowed(self):
        self.assertEqual(self.check_source('AppButton(onPressed: null, label: "Save");', 'lib/features/example/presentation/view.dart'), 0)

    def test_previously_exempt_button_is_rejected(self):
        self.assertEqual(self.check_source('IconButton.filled(onPressed: null, icon: Icon(Icons.add));', 'lib/features/sessions/presentation/new_session_dock.dart'), 1)

    def test_elevated_button_is_rejected(self):
        self.assertEqual(self.check_source('ElevatedButton(onPressed: null, child: Text("Save"));', 'lib/features/example/presentation/view.dart'), 1)

    def test_material_field_is_rejected(self):
        self.assertEqual(self.check_source('TextField();', 'lib/features/example/presentation/view.dart'), 1)

    def test_material_dialog_is_rejected(self):
        self.assertEqual(self.check_source('AlertDialog();', 'lib/features/example/presentation/view.dart'), 1)

    def test_shared_field_and_dialog_are_allowed(self):
        self.assertEqual(self.check_source('AppDialog(content: AppTextField());', 'lib/features/example/presentation/view.dart'), 0)


if __name__ == '__main__':
    unittest.main()
