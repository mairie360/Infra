"""Secrets handed to the reusable CICD workflows: python3 -m unittest discover -s tests

The release secrets live in the Prod environment (main only) and reach the prod
promotion alone; pull request runs only get the low-quota key of the AI reviews.
The workflows are read job by job (quoted keys included): every call of a mairie360/CICD
workflow passes exactly the secrets that workflow reads, each as a direct
`${{ secrets.<same name> }}`, and no other job reads a release secret, whatever the notation.
"""

import os
import re
import subprocess

RELEASE_SECRETS = {"RELEASE_APP_ID", "RELEASE_APP_PK", "ANTHROPIC_API_KEY"}
SECRET_READ = re.compile(r"secrets\s*(?:\.\s*([A-Za-z0-9_]+)|\[\s*['\"]([A-Za-z0-9_]+)['\"]\s*\])", re.IGNORECASE)
REVIEW = ["ANTHROPIC_REVIEW_API_KEY", "ANTHROPIC_WORKSPACE_ID"]
BUILD = ["CODECOV_TOKEN", "N8N_WEBHOOK_SECRET"]
RELEASE_APP = ["RELEASE_APP_ID", "RELEASE_APP_PK"]
# Secrets each mairie360/CICD reusable workflow reads, by called workflow (`[dry-run]`: nightly gates).
EXPECTED = {
    "APIs_cicd.yml": REVIEW + BUILD,
    "BFFs-cicd.yml": REVIEW + BUILD,
    "front-libs-cicd.yml": REVIEW + BUILD,
    "back-lib-cicd.yml": ["CARGO_REGISTRY_TOKEN"] + BUILD + RELEASE_APP,
    "bffs-lib-cicd.yml": BUILD,
    "database_cicd.yml": BUILD,
    "frontend-cicd.yml": BUILD,
    "frontend-dev-exception.yml": [],
    "gdpr-pr-cicd.yml": REVIEW,
    "promote-prod.yml": ["ANTHROPIC_API_KEY", "N8N_WEBHOOK_SECRET"] + REVIEW + RELEASE_APP,
    "promote-prod.yml [dry-run]": ["N8N_WEBHOOK_SECRET"] + REVIEW,
    "promote-staging.yml": ["N8N_WEBHOOK_SECRET"],
    "promote-staging.yml [dry-run]": ["N8N_WEBHOOK_SECRET"],
    "terraform_cicd.yml": ["N8N_WEBHOOK_SECRET"],
}
# The nightly prod dry run only hands the review key over when it asks for the AI review.
DRY_RUN_REVIEW = "${{ needs.check.outputs.ai == 'true' && secrets.ANTHROPIC_REVIEW_API_KEY || '' }}"
CICD_WORKFLOW = re.compile(r"^mairie360/CICD/\.github/workflows/([^@]+)@")


def strip_comment(line):
    return re.sub(r"(^|\s)#.*$", "", line).rstrip()


def unquote(text):
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
        return text[1:-1]
    return text


def key_value(line):
    """`key: value` of a block mapping line, the key unquoted; None for another line."""
    match = re.match(r"""^\s*("[^"]*"|'[^']*'|[^\s:'"][^:]*?)\s*:(?:\s+(.*))?$""", line)
    return (unquote(match.group(1)), (match.group(2) or "").strip()) if match else None


def parse_jobs(text):
    """Jobs of a workflow: name, `uses`, `secrets` (a scalar or a key -> value map), own lines."""
    jobs, in_jobs, job, in_secrets = [], False, None, False
    for raw in text.split("\n"):
        line = strip_comment(raw)
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        entry = key_value(line)
        if indent == 0:
            in_jobs, job = bool(entry) and entry[0] == "jobs" and not entry[1], None
            continue
        if not in_jobs:
            continue
        if indent == 2 and entry and not entry[1]:
            job = {"name": entry[0], "uses": "", "secrets": None, "lines": []}
            jobs.append(job)
            in_secrets = False
            continue
        if job is None:
            continue
        job["lines"].append(line)
        if in_secrets and indent <= 4:
            in_secrets = False
        if in_secrets:
            if entry:
                job["secrets"][entry[0]] = unquote(entry[1])
            continue
        if indent == 4 and entry and entry[0] == "uses":
            job["uses"] = unquote(entry[1])
        if indent == 4 and entry and entry[0] == "secrets":
            value = unquote(entry[1])
            job["secrets"] = value if value else {}
            in_secrets = not value
    return jobs


def release_reads(text):
    return sum(1 for m in SECRET_READ.finditer(text) if (m.group(1) or m.group(2)).upper() in RELEASE_SECRETS)
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDER = os.path.join(REPO, ".github", "workflows")
RELEASE_JOBS = {"promote-prod.yml:promote"}


def workflows():
    for file in sorted(f for f in os.listdir(FOLDER) if re.search(r"\.ya?ml$", f)):
        with open(os.path.join(FOLDER, file), encoding="utf-8") as handle:
            text = handle.read()
        yield file, "\n".join(strip_comment(line) for line in text.split("\n")), parse_jobs(text)


def cicd_calls():
    for file, _, jobs in workflows():
        for job in jobs:
            called = CICD_WORKFLOW.match(job["uses"])
            if called:
                callee = called.group(1) + (" [dry-run]" if file == "nightly-gates.yml" else "")
                mapping = job["secrets"] if isinstance(job["secrets"], dict) else {}
                yield f"{file}:{job['name']}", callee, mapping


class CiSecrets(unittest.TestCase):
    def test_mair_681_every_workflow_with_jobs_is_read(self):
        for file, live, jobs in workflows():
            if re.search(r"^['\"]?jobs['\"]?\s*:", live, re.M):
                self.assertTrue(jobs, file)

    def test_mair_681_no_job_inherits_every_secret_or_lists_them_inline(self):
        for file, _, jobs in workflows():
            for job in jobs:
                self.assertNotIsInstance(job["secrets"], str, f"{file}:{job['name']}")

    def test_mair_681_each_cicd_call_passes_exactly_the_secrets_the_workflow_reads(self):
        for where, callee, mapping in cicd_calls():
            self.assertIn(callee, EXPECTED, where)
            self.assertEqual(sorted(mapping), sorted(EXPECTED[callee]), where)

    def test_mair_681_each_secret_handed_over_is_a_direct_read_of_the_same_name(self):
        for where, callee, mapping in cicd_calls():
            for key, value in mapping.items():
                dry_run_review = callee == "promote-prod.yml [dry-run]" and key == "ANTHROPIC_REVIEW_API_KEY"
                self.assertEqual(value, DRY_RUN_REVIEW if dry_run_review else "${{ secrets.%s }}" % key, where)

    def test_mair_681_release_secrets_only_read_by_the_prod_promotion_job(self):
        for file, live, jobs in workflows():
            allowed = sum(release_reads("\n".join(job["lines"])) for job in jobs if f"{file}:{job['name']}" in RELEASE_JOBS)
            self.assertEqual(release_reads(live), allowed, file)

    def test_mair_681_pull_requests_get_their_gdpr_review(self):
        self.assertTrue(any(callee == "gdpr-pr-cicd.yml" for _, callee, _ in cicd_calls()))

    def test_mair_681_release_journal_is_no_longer_tracked(self):
        tracked = subprocess.run(["git", "-C", REPO, "ls-files", "--", "RELEASE_JOURNAL.md"], capture_output=True, text=True, check=True)
        self.assertEqual(tracked.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
