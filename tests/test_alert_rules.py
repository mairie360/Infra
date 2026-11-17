"""MAIR-621/622: the alert rules of alerts/ and scripts/push-alert-rules.sh.

python3 -m unittest discover -s tests

curl and scripts/tf.sh are stubbed: nothing reaches Scaleway.
"""

import os
import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest

import yaml

REPO = pathlib.Path(__file__).resolve().parent.parent
RULE_FILES = sorted((REPO / "alerts").glob("*/*.yml"))


class RuleFiles(unittest.TestCase):
    def test_each_file_is_one_valid_rule_group(self):
        self.assertTrue(RULE_FILES)
        for path in RULE_FILES:
            group = yaml.safe_load(path.read_text())
            self.assertIsInstance(group.get("name"), str, path)
            self.assertNotIn("groups", group, f"{path}: one group per file, no top list")
            for rule in group["rules"]:
                self.assertTrue(rule.get("alert") and rule.get("expr"), path)
                self.assertEqual(rule["labels"]["severity"], "critical", path)
                self.assertIn("summary", rule["annotations"], path)

    def test_promtool_accepts_them(self):
        if not shutil.which("promtool"):
            self.skipTest("promtool not installed")
        for path in RULE_FILES:
            with tempfile.NamedTemporaryFile("w", suffix=".yml") as f:
                yaml.safe_dump({"groups": [yaml.safe_load(path.read_text().replace("__ENV__", "dev"))]}, f)
                f.flush()
                result = subprocess.run(["promtool", "check", "rules", f.name], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_the_probe_alerts_on_down_unreachable_and_silent_probe(self):
        alerts = {r["alert"]: r for r in yaml.safe_load((REPO / "alerts/group/probes.yml").read_text())["rules"]}
        self.assertEqual(set(alerts), {"SiteDown", "SiteUnreachable", "ProbeSilent"})
        self.assertIn('http_status_class="2xx"', alerts["SiteDown"]["expr"])
        self.assertIn("absent_over_time", alerts["ProbeSilent"]["expr"],
                      "a dead probe must alert too, not just look like a quiet night")

    def test_a_missed_or_never_reported_backup_alerts(self):
        """MAIR-622: a failed night and a CronJob that never reports both alert."""
        group = yaml.safe_load((REPO / "alerts/instance/backups.yml").read_text().replace("__ENV__", "prod"))
        self.assertEqual(group["name"], "backups-prod")
        rule = group["rules"][0]
        self.assertEqual(rule["alert"], "BackupMissed")
        self.assertIn("> 93600", rule["expr"], "26 h: one daily run plus margin")
        self.assertIn("absent_over_time", rule["expr"])
        self.assertIn("mairie360_backup_last_success_timestamp_seconds", rule["expr"],
                      "the metric Deploiment charts/backup pushes")
        self.assertEqual(rule["labels"]["env"], "prod")


FAKE_TF = textwrap.dedent("""\\
    #!/usr/bin/env bash
    case "$*" in
      "orgs/mairie360 output -json probes") echo '{"metrics_url": "https://probes.example/"}' ;;
      "orgs/mairie360 output -json instances")
        echo '{"dev": {"cockpit_metrics_url": "https://dev.example"}, "prod": {"cockpit_metrics_url": "https://prod.example"}}' ;;
      *) echo "unexpected tf.sh $*" >&2; exit 9 ;;
    esac
""")

FAKE_CURL = textwrap.dedent("""\\
    #!/usr/bin/env bash
    url=""; data=""
    for a in "$@"; do
      case "$a" in https://*) url=$a ;; @*) data=${a#@} ;; esac
      case "$a" in X-Auth-Token:*) echo "TOKEN $a" >> "$CALLS" ;; esac
    done
    echo "POST $url" >> "$CALLS"
    cat "$data" >> "$CALLS"
    case "$url" in *"${FAIL_URL:-none}"*) printf 500 ;; *) printf 202 ;; esac
""")


class PushAlertRules(unittest.TestCase):
    def setUp(self):
        self.work = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.work)
        for d in ("scripts", "orgs/mairie360", "bin", "alerts/group", "alerts/instance"):
            (self.work / d).mkdir(parents=True)
        shutil.copy(REPO / "scripts/push-alert-rules.sh", self.work / "scripts")
        (self.work / "alerts/group/probes.yml").write_text("name: external-probe\nrules: []\n")
        (self.work / "alerts/instance/backups.yml").write_text("name: backups-__ENV__\nrules: []\n")
        for path, body in ((self.work / "scripts/tf.sh", FAKE_TF), (self.work / "bin/curl", FAKE_CURL)):
            path.write_text(body)
            path.chmod(0o755)
        self.calls = self.work / "calls"
        self.calls.touch()

    def run_script(self, *args, **env):
        full = dict(os.environ, PATH=f"{self.work / 'bin'}:{os.environ['PATH']}", CALLS=str(self.calls),
                    SCW_SECRET_KEY="iam-secret")
        full.update(env)
        return subprocess.run(["bash", str(self.work / "scripts/push-alert-rules.sh"), *args],
                              env=full, capture_output=True, text=True)

    def test_group_rules_to_the_probes_source_instance_rules_to_each_instance(self):
        result = self.run_script("mairie360")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text()
        self.assertIn("POST https://probes.example/prometheus/config/v1/rules/probes\nname: external-probe", calls)
        self.assertIn("POST https://dev.example/prometheus/config/v1/rules/backups\nname: backups-dev", calls)
        self.assertIn("POST https://prod.example/prometheus/config/v1/rules/backups\nname: backups-prod", calls)
        self.assertIn("TOKEN X-Auth-Token: iam-secret", calls)
        self.assertNotIn("iam-secret", result.stdout + result.stderr)

    def test_a_refused_push_fails_the_run(self):
        result = self.run_script("mairie360", FAIL_URL="prod.example")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ruler answered 500", result.stderr)

    def test_needs_the_key_and_a_known_org(self):
        self.assertNotEqual(self.run_script("mairie360", SCW_SECRET_KEY="").returncode, 0)
        self.assertEqual(self.run_script("nope").returncode, 2)


if __name__ == "__main__":
    unittest.main()
