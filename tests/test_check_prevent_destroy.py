"""Unit tests of tests/check_prevent_destroy.py: python3 -m unittest discover -s tests"""

import importlib.util
import pathlib
import unittest

SPEC = importlib.util.spec_from_file_location(
    "check_prevent_destroy", pathlib.Path(__file__).with_name("check_prevent_destroy.py")
)
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)


def labels(text):
    return [label for _, label in check.unprotected(text)]


PROTECTED = 'resource "a" "b" {\n  x = 1\n  lifecycle {\n    prevent_destroy = true\n  }\n}\n'


class PreventDestroy(unittest.TestCase):
    def test_protected_resource_passes(self):
        self.assertEqual(labels(PROTECTED), [])

    def test_missing_lifecycle_fails(self):
        self.assertEqual(labels('resource "a" "b" {\n  x = 1\n}\n'), ["a.b"])

    def test_commented_setting_fails(self):
        # CodeRabbit on Infra#2: a commented line used to count.
        for comment in ("#", "//"):
            text = f'resource "a" "b" {{\n  lifecycle {{\n    {comment} prevent_destroy = true\n  }}\n}}\n'
            self.assertEqual(labels(text), ["a.b"], comment)
        text = 'resource "a" "b" {\n  lifecycle {\n    /* prevent_destroy = true */\n  }\n}\n'
        self.assertEqual(labels(text), ["a.b"])

    def test_false_fails(self):
        text = 'resource "a" "b" {\n  lifecycle {\n    prevent_destroy = false\n  }\n}\n'
        self.assertEqual(labels(text), ["a.b"])

    def test_setting_outside_lifecycle_fails(self):
        self.assertEqual(labels('resource "a" "b" {\n  prevent_destroy = true\n}\n'), ["a.b"])
        text = 'resource "a" "b" {\n  tags {\n    prevent_destroy = true\n  }\n}\n'
        self.assertEqual(labels(text), ["a.b"])
        text = 'resource "a" "b" {\n  lifecycle {\n    x {\n      prevent_destroy = true\n    }\n  }\n}\n'
        self.assertEqual(labels(text), ["a.b"])

    def test_setting_in_string_or_heredoc_fails(self):
        text = 'resource "a" "b" {\n  d = "lifecycle { prevent_destroy = true }"\n}\n'
        self.assertEqual(labels(text), ["a.b"])
        text = 'resource "a" "b" {\n  d = <<EOT\nlifecycle {\n  prevent_destroy = true\n}\nEOT\n}\n'
        self.assertEqual(labels(text), ["a.b"])

    def test_braces_in_strings_do_not_confuse_blocks(self):
        text = (
            'resource "a" "one" {\n  d = "}"\n  lifecycle {\n    prevent_destroy = true\n  }\n}\n'
            'resource "a" "two" {\n  d = "{"\n}\n'
        )
        self.assertEqual(labels(text), ["a.two"])

    def test_only_resources_are_checked(self):
        self.assertEqual(labels('data "a" "b" {\n}\nmodule "m" {\n  source = "./x"\n}\n'), [])

    def test_line_number(self):
        self.assertEqual(check.unprotected('\n\nresource "a" "b" {\n}\n'), [(3, "a.b")])

    def test_repository_is_protected(self):
        # No exemption any more: the state bucket ACL is protected too.
        root = pathlib.Path(__file__).resolve().parent.parent
        files = check.tracked_tf_files(root)
        self.assertTrue(files)
        self.assertEqual(check.main([str(f) for f in files]), 0)


if __name__ == "__main__":
    unittest.main()
