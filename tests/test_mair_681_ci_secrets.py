"""Secrets handed to the reusable CICD workflows: python3 -m unittest discover -s tests

The release secrets live in the Prod environment (main only) and reach the prod promotion
alone; pull request runs only get the low-quota key of the AI reviews. The workflows are read
job by job, so a quoted `inherit`, a key mapped from another secret or a release secret read by
another job of the same file are caught too.
"""

import os
import re
import subprocess
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RELEASE_JOBS = {"promote-prod.yml:promote"}
RELEASE = re.compile(r"secrets\.(RELEASE_APP_ID|RELEASE_APP_PK|ANTHROPIC_API_KEY)\b")
REVIEW_CALLERS = re.compile(
    r"mairie360/CICD/\.github/workflows/(APIs_cicd|BFFs-cicd|front-libs-cicd|gdpr-pr-cicd|promote-prod)\.yml@"
)


def strip_comment(line):
    return re.sub(r"(^|\s)#.*$", "", line).rstrip()


def parse_jobs(text):
    """Jobs of a workflow: name, `uses`, `secrets` (a scalar or a key -> expression map), own lines."""
    jobs, in_jobs, job, in_secrets = [], False, None, False
    for raw in text.split("\n"):
        line = strip_comment(raw)
        if re.match(r"^jobs:\s*$", line):
            in_jobs = True
            continue
        if not in_jobs or not line.strip():
            continue
        if re.match(r"^\S", line):
            in_jobs, job = False, None
            continue
        header = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if header:
            job = {"name": header.group(1), "uses": "", "secrets": None, "lines": []}
            jobs.append(job)
            in_secrets = False
            continue
        if job is None:
            continue
        job["lines"].append(line)
        indent = len(line) - len(line.lstrip(" "))
        if in_secrets and indent <= 4:
            in_secrets = False
        if in_secrets:
            entry = re.match(r"^\s+([A-Za-z0-9_]+):\s*(.+)$", line)
            if entry:
                job["secrets"][entry.group(1)] = entry.group(2).strip()
            continue
        uses = re.match(r"^    uses:\s*(\S+)", line)
        if uses:
            job["uses"] = uses.group(1).strip("'\"")
        secrets = re.match(r"^    secrets:\s*(.*)$", line)
        if secrets:
            value = secrets.group(1).strip().strip("'\"")
            if value:
                job["secrets"] = value
            else:
                job["secrets"], in_secrets = {}, True
    return jobs


def jobs_of(file):
    with open(os.path.join(REPO, ".github", "workflows", file), encoding="utf-8") as handle:
        text = handle.read()
    return text, parse_jobs(text)


WORKFLOWS = sorted(f for f in os.listdir(os.path.join(REPO, ".github", "workflows")) if re.search(r"\.ya?ml$", f))


class CiSecrets(unittest.TestCase):
    def test_mair_681_no_reusable_workflow_call_inherits_every_secret(self):
        for file in WORKFLOWS:
            for job in jobs_of(file)[1]:
                self.assertNotIsInstance(job["secrets"], str, f"{file}:{job['name']}")

    def test_mair_681_each_secret_is_read_from_the_secret_of_the_same_name(self):
        for file in WORKFLOWS:
            for job in jobs_of(file)[1]:
                mapping = job["secrets"] if isinstance(job["secrets"], dict) else {}
                for key, expression in mapping.items():
                    self.assertEqual(re.findall(r"secrets\.([A-Za-z0-9_]+)", expression), [key], f"{file}:{job['name']}")

    def test_mair_681_release_secrets_only_read_by_the_prod_promotion_job(self):
        for file in WORKFLOWS:
            text, jobs = jobs_of(file)
            live = "\n".join(strip_comment(line) for line in text.split("\n"))
            allowed = sum(len(RELEASE.findall("\n".join(job["lines"]))) for job in jobs if f"{file}:{job['name']}" in RELEASE_JOBS)
            self.assertEqual(len(RELEASE.findall(live)), allowed, file)

    def test_mair_681_every_ai_review_gets_its_dedicated_key(self):
        jobs = [(file, job) for file in WORKFLOWS for job in jobs_of(file)[1]]
        for file, job in jobs:
            if REVIEW_CALLERS.search(job["uses"]):
                self.assertIsInstance(job["secrets"], dict, f"{file}:{job['name']}")
                self.assertIn("ANTHROPIC_REVIEW_API_KEY", job["secrets"], f"{file}:{job['name']}")
        self.assertTrue(any("gdpr-pr-cicd.yml@" in job["uses"] for _, job in jobs))

    def test_mair_681_release_journal_is_no_longer_tracked(self):
        tracked = subprocess.run(["git", "-C", REPO, "ls-files", "--", "RELEASE_JOURNAL.md"], capture_output=True, text=True, check=True)
        self.assertEqual(tracked.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
