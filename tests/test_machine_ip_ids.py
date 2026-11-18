"""MAIR-1075: the plan of the imported machines proposed five in-place updates forever.

python3 -m unittest discover -s tests

An imported machine reads back an empty ip_ids from the provider, so every plan
wanted to attach the two addresses it already has. The machine module must
ignore ip_ids after creation, keep listing both addresses for a new machine, and
keep ignoring the fields it already did. terraform test cannot observe a
lifecycle block against a mocked provider (modules/machine/tests covers the
creation side), hence this text check, which reads the active code only: a
commented-out line never satisfies it.
"""

import pathlib
import re
import unittest

MODULE = pathlib.Path(__file__).resolve().parent.parent / "modules/machine/main.tf"


def active(text):
    """The HCL without its # and // comments."""
    return "\n".join(re.sub(r"(#|//).*", "", line) for line in text.splitlines())


def server():
    text = active(MODULE.read_text())
    return text[text.index('resource "scaleway_instance_server" "this"'):]


def lifecycle():
    body = server()
    return body[body.index("lifecycle"):]


class MachineIpIds(unittest.TestCase):
    def test_ip_ids_is_ignored_after_creation(self):
        ignored = re.search(r"ignore_changes\s*=\s*\[([^\]]*)\]", lifecycle())
        self.assertIsNotNone(ignored, "the server has no active ignore_changes")
        fields = {f.strip() for f in ignored.group(1).split(",") if f.strip()}
        self.assertLessEqual({"image", "ip_id", "ip_ids", "user_data", "cloud_init"}, fields)

    def test_a_new_machine_still_gets_both_addresses(self):
        ids = re.search(r"^\s*ip_ids\s*=\s*\[([^\]]*)\]", server(), re.M)
        self.assertIsNotNone(ids, "the server has no active ip_ids")
        self.assertEqual(
            {a.strip() for a in ids.group(1).split(",") if a.strip()},
            {"scaleway_instance_ip.v4.id", "scaleway_instance_ip.v6.id"},
        )

    def test_the_server_stays_protected(self):
        self.assertRegex(lifecycle(), r"prevent_destroy\s*=\s*true")

    def test_comments_never_count(self):
        self.assertNotIn("ip_ids", active("# ignore_changes = [ip_ids]\n// ip_ids = []"))


if __name__ == "__main__":
    unittest.main()
