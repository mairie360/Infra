"""MAIR-619: scripts/issue-bucket-keys.sh puts one key per bucket into the vault.

python3 -m unittest discover -s tests

scw and scripts/tf.sh are stubbed: nothing reaches Scaleway. The fake scw logs
every call and what it receives on stdin (the stored version); FAKE_ENABLED
lists the secrets that already have an enabled version.
"""

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent

BUCKET_KEYS = {
    "dev/backup": {"env": "dev", "purpose": "backup", "name": "mairie360-backups-dev",
                   "secret": "/mairie360/dev/backup-s3-key", "application_id": "app-dev-backup"},
    "prod/elearning": {"env": "prod", "purpose": "elearning", "name": "mairie360-elearning-prod",
                       "secret": "/mairie360/prod/elearning-s3-key", "application_id": "app-prod-elearning"},
}

FAKE_TF = textwrap.dedent("""\
    #!/usr/bin/env bash
    [ "$*" = "iam output -json bucket_keys" ] || { echo "unexpected tf.sh $*" >&2; exit 9; }
    cat "$BUCKET_KEYS_FILE"
""")

FAKE_SCW = textwrap.dedent("""\
    #!/usr/bin/env bash
    echo "scw $*" >> "$CALLS"
    arg() { for a in "$@"; do case "$a" in "$KEY="*) echo "${a#*=}";; esac; done; }
    case "$1 $2 $3" in
      "secret secret list")
        KEY=name; n=$(arg "$@"); KEY=path; p=$(arg "$@")
        echo "[{\\"id\\": \\"sec:$p/$n\\"}]" ;;
      "secret version list")
        KEY=secret-id; s=$(arg "$@")
        case " ${FAKE_ENABLED:-} " in *" ${s#sec:} "*) echo '[{"status":"enabled"}]' ;; *) echo '[]' ;; esac ;;
      "iam api-key list") echo '[{"access_key":"SCWOLD"}]' ;;
      "iam api-key create") echo '{"access_key":"SCWNEW","secret_key":"very-secret"}' ;;
      "secret version create") echo "STDIN $(cat)" >> "$CALLS"; echo '{}' ;;
    esac
""")


class IssueBucketKeys(unittest.TestCase):
    def setUp(self):
        self.work = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.work)
        (self.work / "scripts").mkdir()
        (self.work / "iam").mkdir()
        (self.work / "bin").mkdir()
        shutil.copy(REPO / "scripts/issue-bucket-keys.sh", self.work / "scripts")
        (self.work / "iam/terraform.tfvars").write_text('project_id = "proj-1"\n')
        for path, body in ((self.work / "scripts/tf.sh", FAKE_TF), (self.work / "bin/scw", FAKE_SCW)):
            path.write_text(body)
            path.chmod(0o755)
        self.keys = self.work / "keys.json"
        self.keys.write_text(json.dumps(BUCKET_KEYS))
        self.calls = self.work / "calls"
        self.calls.touch()

    def run_script(self, *args, **env):
        full = dict(os.environ, PATH=f"{self.work / 'bin'}:{os.environ['PATH']}", CALLS=str(self.calls),
                    BUCKET_KEYS_FILE=str(self.keys), **env)
        return subprocess.run(["bash", str(self.work / "scripts/issue-bucket-keys.sh"), *args],
                              env=full, capture_output=True, text=True)

    def calls_text(self):
        return self.calls.read_text()

    def test_each_bucket_gets_a_key_of_its_own_application_in_its_secret(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls_text()
        self.assertIn("iam api-key create application-id=app-dev-backup default-project-id=proj-1", calls)
        self.assertIn("iam api-key create application-id=app-prod-elearning default-project-id=proj-1", calls)
        self.assertIn("secret version create region=fr-par secret-id=sec:/mairie360/dev/backup-s3-key disable-previous=true", calls)
        self.assertIn('STDIN {"access_key":"SCWNEW","secret_key":"very-secret"}', calls)

    def test_the_secret_key_is_never_printed(self):
        result = self.run_script()
        self.assertNotIn("very-secret", result.stdout + result.stderr)

    def test_a_bucket_with_a_key_is_skipped_without_rotate(self):
        result = self.run_script(FAKE_ENABLED="/mairie360/dev/backup-s3-key")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("application-id=app-dev-backup default", self.calls_text())
        self.assertIn("dev/backup: /mairie360/dev/backup-s3-key already holds a key", result.stdout)

    def test_rotate_replaces_and_lists_the_old_keys_to_delete(self):
        result = self.run_script("--rotate", "dev/backup", FAKE_ENABLED="/mairie360/dev/backup-s3-key")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("application-id=app-dev-backup default", self.calls_text())
        self.assertNotIn("app-prod-elearning default", self.calls_text())
        self.assertIn("scw iam api-key delete SCWOLD", result.stdout)
        self.assertNotIn("api-key delete", self.calls_text(), "old keys are only deleted after the reseal")

    def test_rotate_needs_an_explicit_bucket(self):
        self.assertEqual(self.run_script("--rotate").returncode, 2)

    def test_unknown_bucket_fails(self):
        result = self.run_script("staging/backup")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("api-key create", self.calls_text())


if __name__ == "__main__":
    unittest.main()
