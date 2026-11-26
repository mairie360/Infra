"""Spoofed e-mail test: verdict script and workflow guards."""
import importlib.util
import unittest
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("spoof_check", REPO / "scripts" / "spoof-check.py")
spoof = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spoof)

EMAIL_FAIL = {"from": "noreply@mairie360-eip.fr", "authentication": {"spf": "fail", "dkim": "none", "dmarc": "fail"}}


class Policy(unittest.TestCase):
    def test_mair_1187_enforced_policy(self):
        self.assertEqual(spoof.dmarc_policy(["v=DMARC1; p=quarantine; rua=mailto:dmarc@mairie360.fr"]), ("quarantine", None))
        self.assertEqual(spoof.dmarc_policy(["v=spf1 -all", "v=DMARC1;p=reject"]), ("reject", None))

    def test_mair_1187_missing_or_duplicate_record(self):
        self.assertEqual(spoof.dmarc_policy([])[1], "0 DMARC records (exactly one expected)")
        self.assertEqual(spoof.dmarc_policy(["v=DMARC1; p=none", "v=DMARC1; p=reject"])[1],
                         "2 DMARC records (exactly one expected)")
        self.assertEqual(spoof.dmarc_policy(["v=DMARC1; rua=mailto:x@y"])[1], "DMARC record without policy")


class Verdict(unittest.TestCase):
    def test_mair_1187_forged_email_judged_fail_passes(self):
        passed, lines = spoof.verdict("reject", None, EMAIL_FAIL)
        self.assertTrue(passed)
        self.assertIn("received from noreply@mairie360-eip.fr: spf=fail dkim=none dmarc=fail", lines)

    def test_mair_1187_forged_email_judged_pass_fails(self):
        email = dict(EMAIL_FAIL, authentication={"spf": "pass", "dkim": "none", "dmarc": "pass"})
        passed, lines = spoof.verdict("reject", None, email)
        self.assertFalse(passed)
        self.assertIn("the forged e-mail was not judged dmarc=fail: it would be delivered", lines)

    def test_mair_1187_policy_none_fails_even_if_judged_fail(self):
        passed, lines = spoof.verdict("none", None, EMAIL_FAIL)
        self.assertFalse(passed)
        self.assertIn("DMARC policy p=none: a forged From: is delivered", lines)

    def test_mair_1187_not_received_fails(self):
        passed, lines = spoof.verdict("reject", None, None)
        self.assertFalse(passed)
        self.assertIn("spoofed e-mail not received: the test proves nothing, look at the run", lines)


class Polling(unittest.TestCase):
    def test_mair_1187_finds_the_email_by_token(self):
        pages = [{"data": [{"id": "a", "subject": "hello"}]},
                 {"data": [{"id": "b", "subject": "mairie360 spoof test 0123abcd"}]}]
        calls = []
        found = spoof.find_email("0123abcd", "key", timeout=60, interval=1,
                                 get=lambda path, key: calls.append(path) or pages[len(calls) - 1],
                                 sleep=lambda s: None, clock=lambda: 0)
        self.assertEqual(found, "b")
        self.assertEqual(calls, ["/emails/receiving", "/emails/receiving"])

    def test_mair_1187_gives_up_after_the_timeout(self):
        ticks = iter([0, 10, 20, 30])
        found = spoof.find_email("0123abcd", "key", timeout=15, interval=5,
                                 get=lambda path, key: {"data": []}, sleep=lambda s: None, clock=lambda: next(ticks))
        self.assertIsNone(found)


class Workflow(unittest.TestCase):
    def setUp(self):
        self.wf = yaml.safe_load((REPO / ".github/workflows/spoof-test.yml").read_text())
        self.job = self.wf["jobs"]["spoof"]

    def test_mair_1187_main_only_in_its_own_environment(self):
        self.assertIn("github.ref == 'refs/heads/main'", self.job["if"])
        self.assertEqual(self.job["environment"], "attack-spoof-test")

    def test_mair_1187_source_always_destroyed(self):
        last = self.job["steps"][-1]
        self.assertEqual(last["if"], "always()")
        self.assertIn("apply -input=false -auto-approve -var enabled=false", last["run"])
        self.assertIn("rm -f attack-source/spoof.auto.tfvars", last["run"])

    def test_mair_1187_only_the_attack_source_root(self):
        runs = " ".join(s.get("run", "") for s in self.job["steps"])
        self.assertNotIn("orgs/", runs)
        self.assertNotIn("iam", runs.replace("iam/", ""))
        self.assertEqual(runs.count("scripts/tf.sh attack-source apply"), 2)

    def test_mair_1187_shares_the_attack_source_lock(self):
        self.assertEqual(self.wf["concurrency"]["group"], "attack-source")
        self.assertFalse(self.wf["concurrency"]["cancel-in-progress"])


if __name__ == "__main__":
    unittest.main()
