"""MAIR-1075: the plan of the imported machines proposed five in-place updates forever.

python3 -m unittest discover -s tests

An imported machine reads back an empty ip_ids from the provider, so every plan
wanted to attach the two addresses it already has. The machine module must
ignore ip_ids after creation, keep listing both addresses for a new machine, and
keep ignoring the fields it already did. terraform test cannot observe a
lifecycle block against a mocked provider, hence this text check.
"""

import pathlib
import re
import unittest

MODULE = pathlib.Path(__file__).resolve().parent.parent / "modules/machine/main.tf"


def lifecycle_of_server(text):
    server = text[text.index('resource "scaleway_instance_server" "this"'):]
    return server[server.index("lifecycle"):]


class MachineIpIds(unittest.TestCase):
    def test_ip_ids_is_ignored_after_creation(self):
        ignored = re.search(r"ignore_changes\s*=\s*\[([^\]]*)\]", lifecycle_of_server(MODULE.read_text()))
        self.assertIsNotNone(ignored, "the server has no ignore_changes")
        fields = {f.strip() for f in ignored.group(1).split(",") if f.strip()}
        self.assertLessEqual({"image", "ip_id", "ip_ids", "user_data", "cloud_init"}, fields)

    def test_a_new_machine_still_gets_both_addresses(self):
        text = MODULE.read_text()
        self.assertIn("ip_ids     = [scaleway_instance_ip.v4.id, scaleway_instance_ip.v6.id]", text)

    def test_the_server_stays_protected(self):
        self.assertIn("prevent_destroy = true", lifecycle_of_server(MODULE.read_text()))


if __name__ == "__main__":
    unittest.main()
