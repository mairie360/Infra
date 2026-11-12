"""Tests of scripts/tf.sh and scripts/bootstrap.sh: python3 -m unittest discover -s tests

terraform and scw are stubbed on PATH: nothing reaches Scaleway. The stubs log
every call; the fake terraform creates the local state on `apply` (local
backend) and answers `state list` from FAKE_STATE_LIST.
"""

import os
import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent

FAKE_TERRAFORM = textwrap.dedent("""\
    #!/usr/bin/env bash
    chdir="${1#-chdir=}"; shift
    override=no; [ -e "$chdir/backend_override.tf" ] && override=yes
    echo "$(basename "$chdir") $* override=$override aws=${AWS_ACCESS_KEY_ID:-}" >> "$CALLS"
    case "$1" in
      apply) [ "${FAKE_APPLY_FAIL:-}" = yes ] && exit 1
             echo '{"resources":[1]}' > "$chdir/terraform.tfstate" ;;
      state) printf '%s' "${FAKE_STATE_LIST:-}" ;;
    esac
    exit 0
""")

FAKE_SCW = textwrap.dedent("""\
    #!/usr/bin/env bash
    echo "scw $*" >> "$CALLS"
    case "$*" in
      "config get access-key") echo SCWACCESS ;;
      "config get secret-key") echo scw-secret ;;
      "object bucket get"*) [ "${FAKE_BUCKET:-}" = yes ] ;;
    esac
""")


class Scripts(unittest.TestCase):
    def setUp(self):
        self.work = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.work)
        for d in ("scripts", "bootstrap", "orgs/x", "bin"):
            (self.work / d).mkdir(parents=True)
        for s in ("tf.sh", "bootstrap.sh"):
            shutil.copy(REPO / "scripts" / s, self.work / "scripts" / s)
        for name, body in (("terraform", FAKE_TERRAFORM), ("scw", FAKE_SCW)):
            path = self.work / "bin" / name
            path.write_text(body)
            path.chmod(0o755)
        self.calls = self.work / "calls"
        self.calls.touch()

    def run_script(self, *args, **env):
        full_env = {k: v for k, v in os.environ.items() if not k.startswith("AWS_")}
        full_env.update(PATH=f"{self.work / 'bin'}:{os.environ['PATH']}", CALLS=str(self.calls), **env)
        return subprocess.run(
            ["bash", *map(str, args)], env=full_env, capture_output=True, text=True, cwd=self.work
        )

    def terraform_calls(self):
        return [line for line in self.calls.read_text().splitlines() if not line.startswith("scw ")]

    # tf.sh

    def test_tf_initialises_even_when_terraform_dir_exists(self):
        # CodeRabbit on Infra#2: `init -backend=false` of the README checks left
        # a .terraform folder and the wrapper skipped the backend init.
        (self.work / "orgs/x/.terraform").mkdir()
        result = self.run_script(self.work / "scripts/tf.sh", "orgs/x", "plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.terraform_calls()
        self.assertEqual([c.split(" override")[0] for c in calls], ["x init -input=false", "x plan"])

    def test_tf_init_is_not_run_twice(self):
        result = self.run_script(self.work / "scripts/tf.sh", "orgs/x", "init", "-upgrade")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c.split(" override")[0] for c in self.terraform_calls()], ["x init -upgrade"])

    def test_tf_takes_backend_credentials_from_scw(self):
        self.run_script(self.work / "scripts/tf.sh", "orgs/x", "plan")
        self.assertTrue(all(c.endswith("aws=SCWACCESS") for c in self.terraform_calls()))

    def test_tf_refuses_an_unknown_root(self):
        result = self.run_script(self.work / "scripts/tf.sh", "orgs/nope", "plan")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.terraform_calls(), [])

    # bootstrap.sh

    def test_first_run_applies_locally_then_migrates(self):
        result = self.run_script(self.work / "scripts/bootstrap.sh", FAKE_STATE_LIST="scaleway_object_bucket.state")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.terraform_calls()
        apply = next(c for c in calls if " apply " in f" {c} ")
        self.assertIn("override=yes", apply, "the first apply uses the local backend")
        migrate = next(c for c in calls if "-migrate-state" in c)
        self.assertIn("override=no", migrate)
        self.assertLess(calls.index(apply), calls.index(migrate))
        self.assertFalse((self.work / "bootstrap/terraform.tfstate").exists())
        self.assertFalse((self.work / "bootstrap/backend_override.tf").exists())

    def test_interrupted_run_applies_locally_then_migrates(self):
        # CodeRabbit on Infra#2: a run stopped after the apply left a local
        # state that the next run never moved into the bucket; and a run
        # stopped after the bucket but before its ACL must create the ACL
        # (local apply) before migrating, not only migrate.
        (self.work / "bootstrap/terraform.tfstate").write_text('{"resources":[1]}')
        result = self.run_script(
            self.work / "scripts/bootstrap.sh", FAKE_BUCKET="yes", FAKE_STATE_LIST="scaleway_object_bucket.state"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.terraform_calls()
        self.assertFalse(any(c.startswith("bootstrap plan") for c in calls), calls)
        apply = next(c for c in calls if c.startswith("bootstrap apply"))
        self.assertIn("override=yes", apply, "the resumed apply uses the local state")
        migrate = next(c for c in calls if "-migrate-state" in c)
        self.assertLess(calls.index(apply), calls.index(migrate))
        self.assertFalse((self.work / "bootstrap/terraform.tfstate").exists())

    def test_failed_apply_keeps_the_local_state_and_removes_the_override(self):
        (self.work / "bootstrap/terraform.tfstate").write_text('{"resources":[1]}')
        result = self.run_script(self.work / "scripts/bootstrap.sh", FAKE_BUCKET="yes", FAKE_APPLY_FAIL="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("-migrate-state" in c for c in self.terraform_calls()))
        self.assertTrue((self.work / "bootstrap/terraform.tfstate").exists())
        self.assertFalse((self.work / "bootstrap/backend_override.tf").exists())

    def test_local_state_is_kept_when_the_bucket_state_is_empty(self):
        (self.work / "bootstrap/terraform.tfstate").write_text('{"resources":[1]}')
        result = self.run_script(self.work / "scripts/bootstrap.sh", FAKE_BUCKET="yes", FAKE_STATE_LIST="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is kept", result.stderr)
        self.assertTrue((self.work / "bootstrap/terraform.tfstate").exists())

    def test_existing_bucket_only_plans(self):
        result = self.run_script(self.work / "scripts/bootstrap.sh", FAKE_BUCKET="yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [c.split(" override")[0] for c in self.terraform_calls()],
            ["bootstrap init -input=false", "bootstrap plan"],
        )


if __name__ == "__main__":
    unittest.main()
