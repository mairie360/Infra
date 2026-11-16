"""MAIR-620: scripts/issue-cockpit-tokens.sh puts each instance's Cockpit token into the vault.

python3 -m unittest discover -s tests

scw and scripts/tf.sh are stubbed: nothing reaches Scaleway.
"""

import os
import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent

FAKE_TF = textwrap.dedent("""\
    #!/usr/bin/env bash
    [ "$*" = "orgs/mairie360 output -json instances" ] || { echo "unexpected tf.sh $*" >&2; exit 9; }
    echo '{"dev": {}, "prod": {}}'
""")

FAKE_SCW = textwrap.dedent("""\
    #!/usr/bin/env bash
    echo "scw $*" >> "$CALLS"
    arg() { for a in "$@"; do case "$a" in "$KEY="*) echo "${a#*=}";; esac; done; }
    case "$1 $2 $3" in
      "secret secret list") KEY=path; p=$(arg "$@"); echo "[{\\"id\\": \\"sec:$p\\"}]" ;;
      "secret version list")
        KEY=secret-id; s=$(arg "$@")
        case " ${FAKE_ENABLED:-} " in *" ${s#sec:} "*) echo '[{"status":"enabled"}]' ;; *) echo '[]' ;; esac ;;
      "cockpit token list") echo '[{"id":"tok-old","name":"mairie360-prod-collector"},{"id":"tok-other","name":"x"}]' ;;
      "cockpit token create") echo '{"id":"tok-new","secret_key":"cockpit-secret"}' ;;
      "secret version create") echo "STDIN $(cat)" >> "$CALLS"; echo '{}' ;;
    esac
""")


class IssueCockpitTokens(unittest.TestCase):
    def setUp(self):
        self.work = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.work)
        for d in ("scripts", "orgs/mairie360", "bin"):
            (self.work / d).mkdir(parents=True)
        shutil.copy(REPO / "scripts/issue-cockpit-tokens.sh", self.work / "scripts")
        (self.work / "orgs/mairie360/terraform.tfvars").write_text('project_id = "proj-1"\n')
        for path, body in ((self.work / "scripts/tf.sh", FAKE_TF), (self.work / "bin/scw", FAKE_SCW)):
            path.write_text(body)
            path.chmod(0o755)
        self.calls = self.work / "calls"
        self.calls.touch()

    def run_script(self, *args, **env):
        full = dict(os.environ, PATH=f"{self.work / 'bin'}:{os.environ['PATH']}", CALLS=str(self.calls), **env)
        return subprocess.run(["bash", str(self.work / "scripts/issue-cockpit-tokens.sh"), *args],
                              env=full, capture_output=True, text=True)

    def test_push_only_token_stored_in_the_instance_secret(self):
        result = self.run_script("mairie360")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text()
        self.assertIn("cockpit token create region=fr-par project-id=proj-1 name=mairie360-dev-collector "
                      "token-scopes.0=write_only_metrics token-scopes.1=write_only_traces", calls)
        self.assertIn("secret-id=sec:/mairie360/prod disable-previous=true", calls)
        self.assertIn("STDIN cockpit-secret\n", calls, "the raw token, as COCKPIT_TOKEN expects")
        self.assertNotIn("cockpit-secret", result.stdout + result.stderr)

    def test_hub_probe_gets_a_metrics_only_token(self):
        """MAIR-621: the external probe on the Argo CD machine only pushes metrics."""
        result = self.run_script("mairie360")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text()
        self.assertIn("name=mairie360-hub-collector token-scopes.0=write_only_metrics -o json", calls)
        self.assertIn("secret-id=sec:/mairie360/hub disable-previous=true", calls)

    def test_existing_token_is_kept_without_rotate(self):
        result = self.run_script("mairie360", "prod", FAKE_ENABLED="/mairie360/prod")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("cockpit token create", self.calls.read_text())

    def test_rotate_lists_only_the_previous_token_of_that_instance(self):
        result = self.run_script("--rotate", "mairie360", "prod", FAKE_ENABLED="/mairie360/prod")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("token-id=tok-old", result.stdout)
        self.assertNotIn("tok-other", result.stdout)
        self.assertNotIn("token delete", self.calls.read_text())

    def test_unknown_org_and_bare_rotate_are_refused(self):
        self.assertEqual(self.run_script("nope").returncode, 2)
        self.assertEqual(self.run_script("--rotate", "mairie360").returncode, 2)


if __name__ == "__main__":
    unittest.main()
