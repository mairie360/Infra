"""MAIR-621/622: the alert rules of alerts/ and scripts/push-alert-rules.sh.

python3 -m unittest discover -s tests

curl and scripts/tf.sh are stubbed: nothing reaches Scaleway.
"""

import os
import pathlib
import re
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
                self.assertTrue(rule.get("expr"), path)
                if "record" in rule:  # carries a value past the ruler's 1 h range limit
                    self.assertRegex(rule["record"], r"^mairie360:", path)
                    continue
                self.assertTrue(rule.get("alert"), path)
                self.assertEqual(rule["labels"]["severity"], "critical", path)
                self.assertIn("summary", rule["annotations"], path)

    def test_mair_628_no_range_over_the_cockpit_ruler_limit(self):
        """The Cockpit ruler refuses any range selector over 1 h ("matrix selector
        range 8h0m0s exceeds maximum allowed limit of 1h0m0s"): one such rule
        makes the whole namespace fail to push."""
        unit = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}
        for path in RULE_FILES:
            for rule in yaml.safe_load(path.read_text())["rules"]:
                for amount, u in re.findall(r"\[(\d+)([smhdw])(?::[^\]]*)?\]", rule["expr"]):
                    self.assertLessEqual(int(amount) * unit[u], 3600,
                                         f"{path.name}: {rule.get('alert') or rule.get('record')} uses [{amount}{u}]")

    def test_promtool_accepts_them(self):
        if not shutil.which("promtool"):
            self.skipTest("promtool not installed")
        for path in RULE_FILES:
            with tempfile.NamedTemporaryFile("w", suffix=".yml") as f:
                yaml.safe_dump({"groups": [yaml.safe_load(path.read_text().replace("__ENV__", "dev"))]}, f)
                f.flush()
                result = subprocess.run(["promtool", "check", "rules", f.name], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_mair_628_rules_fire_above_their_thresholds_only(self):
        """promtool unit tests of tests/promtool/ against the rule files."""
        if not shutil.which("promtool"):
            self.skipTest("promtool not installed")
        with tempfile.TemporaryDirectory() as d:
            for path in RULE_FILES:
                group = yaml.safe_load(path.read_text().replace("__ENV__", "dev"))
                (pathlib.Path(d) / f"{path.parent.name}-{path.name}").write_text(yaml.safe_dump({"groups": [group]}))
            for test in sorted((REPO / "tests/promtool").glob("*.yml")):
                shutil.copy(test, d)
                result = subprocess.run(["promtool", "test", "rules", test.name], cwd=d, capture_output=True, text=True)
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
        rules = {r.get("record") or r["alert"] + ("/never" if "absent" in r["expr"] else ""): r for r in group["rules"]}
        latest = "mairie360:backup_last_success_timestamp_seconds:latest"
        self.assertIn("mairie360_backup_last_success_timestamp_seconds", rules[latest]["expr"],
                      "the metric Deploiment charts/backup pushes")
        self.assertIn("> 25200", rules["BackupMissed"]["expr"], "7 h: one run every 6 h plus margin")
        self.assertIn(latest, rules["BackupMissed"]["expr"])
        self.assertEqual(rules["BackupMissed/never"]["for"], "7h", "a CronJob that never reports alerts too")
        for name in ("BackupMissed", "BackupMissed/never"):
            self.assertEqual(rules[name]["labels"]["env"], "prod")

    def test_mair_631_a_missed_or_slow_restore_test_alerts(self):
        rules = yaml.safe_load((REPO / "alerts/instance/backups.yml").read_text())["rules"]
        missed = [r for r in rules if r.get("alert") == "RestoreTestMissed"]
        self.assertIn("> 691200", missed[0]["expr"], "8 days: one weekly test plus margin")
        self.assertIn("mairie360:restore_test_last_success_timestamp_seconds:latest", missed[0]["expr"])
        self.assertEqual([r["for"] for r in missed if "absent" in r["expr"]], ["8d"],
                         "a test that never reported must alert too")
        slow = next(r for r in rules if r.get("alert") == "RestoreTooSlow")["expr"]
        self.assertIn("mairie360:restore_test_duration_seconds:latest", slow)
        self.assertIn("> 3600", slow, "the database restore must leave room in the 2 h RTO")
        records = {r["record"]: r["expr"] for r in rules if "record" in r}
        self.assertIn("mairie360_restore_test_last_success_timestamp_seconds",
                      records["mairie360:restore_test_last_success_timestamp_seconds:latest"])
        self.assertIn("mairie360_restore_test_duration_seconds", records["mairie360:restore_test_duration_seconds:latest"])

    def test_mair_628_instance_rules_cover_the_agreed_thresholds(self):
        group = yaml.safe_load((REPO / "alerts/instance/platform.yml").read_text().replace("__ENV__", "prod"))
        self.assertEqual(group["name"], "platform-prod")
        alerts = {r["alert"]: r for r in group["rules"] if "alert" in r}
        self.assertEqual(set(alerts), {
            "DiskAlmostFull", "MemoryHigh", "ContainerCrashLooping", "ContainerOOMKilled",
            "CertificateExpiresSoon", "HighErrorRate", "PostgresConnectionsHigh", "PostgresDown",
            "PostgresExporterSilent", "InstanceMetricsSilent"})
        self.assertIn("> 0.8", alerts["DiskAlmostFull"]["expr"])
        self.assertIn("> 0.9", alerts["MemoryHigh"]["expr"])
        self.assertEqual(alerts["MemoryHigh"]["for"], "10m")
        self.assertIn('reason="CrashLoopBackOff"', alerts["ContainerCrashLooping"]["expr"])
        self.assertIn('reason="OOMKilled"', alerts["ContainerOOMKilled"]["expr"])
        self.assertIn("< 14 * 86400", alerts["CertificateExpiresSoon"]["expr"])
        self.assertIn('code=~"5.."', alerts["HighErrorRate"]["expr"])
        self.assertIn("> 0.02", alerts["HighErrorRate"]["expr"])
        self.assertIn("[5m]", alerts["HighErrorRate"]["expr"])
        self.assertIn("pg_settings_max_connections", alerts["PostgresConnectionsHigh"]["expr"])
        self.assertIn("> 0.8", alerts["PostgresConnectionsHigh"]["expr"])
        self.assertIn("absent_over_time", alerts["InstanceMetricsSilent"]["expr"],
                      "a dead collector must alert, or every other instance alert is blind")
        for rule in alerts.values():
            self.assertEqual(rule["labels"]["env"], "prod", rule["alert"])

    def test_mair_628_argocd_prod_degraded_or_out_of_sync_for_30_minutes(self):
        alerts = {r["alert"]: r for r in yaml.safe_load((REPO / "alerts/group/argocd.yml").read_text())["rules"]}
        for name, status in (("ArgoCDProdUnhealthy", "Degraded"), ("ArgoCDProdOutOfSync", "OutOfSync")):
            self.assertEqual(alerts[name]["for"], "30m", name)
            self.assertIn(status, alerts[name]["expr"], name)
            self.assertIn('name=~"prod|.+-prod"', alerts[name]["expr"], "the prod instance and its add-ons")
        self.assertIn("absent_over_time", alerts["ArgoCDMetricsSilent"]["expr"])

    def test_mair_628_an_unreachable_instance_alerts_within_2_minutes(self):
        alerts = {r["alert"]: r for r in yaml.safe_load((REPO / "alerts/group/probes.yml").read_text())["rules"]}
        self.assertEqual(alerts["SiteDown"]["for"], "2m")
        self.assertEqual(alerts["SiteUnreachable"]["for"], "2m")


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
