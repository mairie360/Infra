"""MAIR-637: every machine of a group made before Terraform is imported, never created again.

python3 -m unittest discover -s tests

terraform test cannot run import blocks against a mocked provider, so the import
list of each orgs/<org>/terraform.tfvars is checked here: one entry per
instance and one for the Argo CD machine, with Scaleway UUIDs.
"""

import pathlib
import re
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"


def block(text, name):
    """Body of the top-level `name = { ... }` assignment of a tfvars file."""
    start = re.search(rf"^{name}\s*=\s*\{{", text, re.M)
    if not start:
        return None
    depth, i = 0, start.end() - 1
    for j in range(i, len(text)):
        depth += {"{": 1, "}": -1}.get(text[j], 0)
        if depth == 0:
            return text[i + 1 : j]
    raise ValueError(f"unbalanced {name}")


def top_keys(body):
    keys, depth = [], 0
    for line in body.splitlines():
        if depth == 0:
            m = re.match(r"\s*([a-z0-9_-]+)\s*=", line)
            if m:
                keys.append(m.group(1))
        depth += line.count("{") - line.count("}")
    return keys


class Imports(unittest.TestCase):
    def test_mairie360_adopts_its_four_console_machines(self):
        text = (REPO / "orgs/mairie360/terraform.tfvars").read_text()
        instances = top_keys(block(text, "instances"))
        imported = block(text, "imported_machines")
        self.assertEqual(set(top_keys(imported)), set(instances) | {"argocd"})
        for line in imported.strip().splitlines():
            for field in ("server_id", "ipv4_id", "ipv6_id"):
                self.assertRegex(line, rf'{field}\s*=\s*"{UUID}"', line)

    def test_block_reader(self):
        body = block('a = { x = { y = 1 }\n z = 2 }\nb = 3\n', "a")
        self.assertEqual(top_keys(body), ["x", "z"])


if __name__ == "__main__":
    unittest.main()
