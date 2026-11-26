"""MAIR-634: every Terraform root locks its state (use_lockfile) and the CI apply can
release that lock, and only that lock."""
import pathlib
import re
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
ROOTS = [p.parent for p in REPO.glob("**/backend.tf") if ".terraform" not in p.parts]


class StateLockTest(unittest.TestCase):
    def test_mair_634_every_backend_locks_the_state(self):
        self.assertEqual({str(r.relative_to(REPO)) for r in ROOTS}, {"attack-source", "bootstrap", "iam", "orgs/mairie360"})
        for root in ROOTS:
            backend = (root / "backend.tf").read_text()
            self.assertRegex(backend, r'backend "s3" \{[^}]*use_lockfile\s*=\s*true', root.name)
            self.assertNotIn("dynamodb", backend, "Scaleway has no DynamoDB: the lock is the S3 lockfile")

    def test_mair_634_roots_require_a_terraform_with_s3_lockfiles(self):
        for root in ROOTS:
            version = re.search(r'required_version\s*=\s*">=\s*1\.(\d+)', (root / "versions.tf").read_text())
            self.assertIsNotNone(version, root.name)
            self.assertGreaterEqual(int(version.group(1)), 11, f"{root.name}: use_lockfile is GA from Terraform 1.11")

    def test_mair_634_the_ci_apply_takes_the_lock_and_plans_do_not(self):
        apply = (REPO / ".github/workflows/apply.yml").read_text()
        applies = [l for l in apply.splitlines() if re.search(r"tf\.sh \"\$ROOT\" apply", l)]
        self.assertTrue(applies)
        for line in applies:
            self.assertNotIn("-lock=false", line, "the CI apply must take the state lock")
        for name in ("plan.yml", "apply.yml"):
            for line in (REPO / ".github/workflows" / name).read_text().splitlines():
                if re.search(r"tf\.sh \"\$ROOT\" plan", line):
                    self.assertIn("-lock=false", line, f"{name}: the plan key is read-only, it cannot write the lock")

    def test_mair_634_the_ci_apply_may_delete_the_lock_objects_only(self):
        buckets = (REPO / "iam/buckets.tf").read_text()
        state = buckets[buckets.index('resource "scaleway_object_bucket_policy" "state"'):]
        state = state[:state.index("lifecycle")]
        lock = re.search(r'Sid\s*=\s*"ci-apply-state-lock"(.*?)\n\s*\},', state, re.S)
        self.assertIsNotNone(lock, "the CI apply cannot release the state lock")
        self.assertRegex(lock.group(1), r"Action\s*=\s*\[\"s3:DeleteObject\"\]")
        self.assertRegex(lock.group(1), r"Resource\s*=\s*\[\"\$\{var.state_bucket\}/\*\.tflock\"\]")
        for sid in ("ci-plan-state", "ci-apply-state"):
            statement = re.search(rf'Sid\s*=\s*"{sid}"(.*?)\n\s*\}},', state, re.S).group(1)
            self.assertNotIn("DeleteObject", statement, f"{sid} must not delete the state itself")


if __name__ == "__main__":
    unittest.main()
