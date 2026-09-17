"""Deterministic package-boundary regression checks using disposable fixtures."""

import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest

from check_architecture import main


class PackageBoundaryTest(unittest.TestCase):
    def check_source(self, source):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            try:
                os.chdir(directory)
                target = Path('packages/design_system/lib/component.dart')
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


if __name__ == '__main__':
    unittest.main()
