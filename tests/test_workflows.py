"""Guards of the CI workflows that hold Scaleway keys (MAIR-803): python3 -m unittest discover -s tests

The apply key can change the infrastructure: it must only be reachable from the
approved `infra-apply` environment, on `main`, applying the plan a reviewer read.
Also tests scripts/plan-comment.sh.
"""

import pathlib
import subprocess
import tempfile
import unittest

import yaml

REPO = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = REPO / ".github/workflows"


def load(name):
    data = yaml.safe_load((WORKFLOWS / name).read_text())
    # PyYAML reads the `on:` key as the boolean True.
    data["on"] = data.pop(True, data.get("on"))
    return data


def steps_text(job):
    return "\n".join(str(step.get("run", "")) + " " + str(step.get("uses", "")) for step in job.get("steps", []))


class Workflows(unittest.TestCase):
    def test_only_the_apply_job_uses_the_apply_environment(self):
        for path in WORKFLOWS.glob("*.yml"):
            for name, job in load(path.name).get("jobs", {}).items():
                env = job.get("environment")
                env = env.get("name") if isinstance(env, dict) else env
                if (path.name, name) != ("apply.yml", "apply"):
                    self.assertNotEqual(env, "infra-apply", f"{path.name}:{name}")

    def test_apply_is_manual_main_only_and_serialised(self):
        wf = load("apply.yml")
        self.assertEqual(list(wf["on"]), ["workflow_dispatch"])
        self.assertEqual(wf["concurrency"], {"group": "infra-apply", "cancel-in-progress": False})
        for name in ("plan", "apply"):
            self.assertIn("github.ref == 'refs/heads/main'", wf["jobs"][name]["if"], name)

    def test_apply_applies_the_plan_the_reviewer_saw(self):
        jobs = load("apply.yml")["jobs"]
        self.assertEqual(jobs["plan"]["environment"], "infra-plan")
        self.assertEqual(jobs["apply"]["environment"], "infra-apply")
        self.assertEqual(jobs["apply"]["needs"], "plan")
        plan, apply = steps_text(jobs["plan"]), steps_text(jobs["apply"])
        self.assertIn("-out=tfplan", plan)
        self.assertIn("GITHUB_STEP_SUMMARY", plan)
        self.assertIn("actions/download-artifact", apply)
        self.assertRegex(apply, r"apply [^\n]*tfplan")
        self.assertNotIn("-auto-approve", apply)
        self.assertNotRegex(apply, r"\bplan\b(?! file)")

    def test_pull_request_plans_never_get_the_apply_key_nor_forks(self):
        wf = load("plan.yml")
        self.assertEqual(list(wf["on"]), ["pull_request"], "never pull_request_target")
        job = wf["jobs"]["plan"]
        self.assertEqual(job["environment"], "infra-plan")
        self.assertIn("head.repo.full_name == github.repository", job["if"])
        self.assertNotIn("apply", steps_text(job))

    def test_plan_errors_reach_the_comment_and_the_summary(self):
        # Infra#4: a plan that failed before terraform ran (no key) posted an empty comment.
        for name, job in (("plan.yml", "plan"), ("apply.yml", "plan")):
            self.assertRegex(steps_text(load(name)["jobs"][job]), r"2>&1 \| tee plan\.txt", name)

    def test_checkouts_do_not_keep_the_token(self):
        for path in WORKFLOWS.glob("*.yml"):
            for name, job in load(path.name).get("jobs", {}).items():
                for step in job.get("steps", []):
                    if str(step.get("uses", "")).startswith("actions/checkout"):
                        self.assertIs(step.get("with", {}).get("persist-credentials"), False, f"{path.name}:{name}")

    def test_third_party_actions_are_pinned_by_sha(self):
        for path in WORKFLOWS.glob("*.yml"):
            for name, job in load(path.name).get("jobs", {}).items():
                for step in job.get("steps", []):
                    uses = str(step.get("uses", ""))
                    if uses and not uses.startswith(("./", "mairie360/")):
                        self.assertRegex(uses, r"@[0-9a-f]{40}$", f"{path.name}:{name}")


class PlanComment(unittest.TestCase):
    def run_script(self, text, code):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
            f.write(text)
        self.addCleanup(pathlib.Path(f.name).unlink)
        result = subprocess.run(
            ["bash", str(REPO / "scripts/plan-comment.sh"), "orgs/x", f.name, str(code)],
            capture_output=True, text=True, check=True,
        )
        return result.stdout

    def test_changes_show_the_plan_line(self):
        out = self.run_script("+ resource\nPlan: 2 to add, 0 to change, 0 to destroy.\n", 2)
        self.assertIn("terraform plan `orgs/x`: changes: Plan: 2 to add, 0 to change, 0 to destroy.", out)
        self.assertIn("+ resource", out)

    def test_no_change_and_error(self):
        self.assertIn(": no change", self.run_script("No changes.\n", 0))
        self.assertIn("**error** (exit code 1)", self.run_script("Error: boom\n", 1))

    def test_long_plans_are_cut_from_the_beginning(self):
        out = self.run_script("start\n" + "x" * 70000 + "\nPlan: 1 to add, 0 to change, 0 to destroy.\n", 2)
        self.assertLess(len(out), 65536)
        self.assertNotIn("start", out)
        self.assertIn("beginning cut", out)
        self.assertIn("Plan: 1 to add", out)


if __name__ == "__main__":
    unittest.main()
