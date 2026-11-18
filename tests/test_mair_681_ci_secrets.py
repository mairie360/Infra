"""Secrets handed to the reusable CICD workflows: python3 -m unittest discover -s tests

The release secrets live in the Prod environment (main only) and reach the prod promotion
alone; pull request runs only get the low-quota key of the AI reviews.
"""

import pathlib
import re
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = sorted((REPO / ".github/workflows").glob("*.y*ml"))
RELEASE_ONLY = {"promote-prod.yml"}


class CiSecrets(unittest.TestCase):
    def test_mair_681_no_workflow_hands_every_secret_to_a_reusable_workflow(self):
        for path in WORKFLOWS:
            self.assertNotRegex(path.read_text(), r"secrets:\s*inherit", path.name)

    def test_mair_681_release_secrets_only_reach_the_prod_promotion(self):
        for path in WORKFLOWS:
            if path.name in RELEASE_ONLY:
                continue
            self.assertIsNone(
                re.search(r"^\s+(RELEASE_APP_ID|RELEASE_APP_PK|ANTHROPIC_API_KEY):", path.read_text(), re.M),
                path.name,
            )

    def test_mair_681_ai_review_of_pull_requests_gets_its_dedicated_key(self):
        text = (REPO / ".github/workflows/gdpr-pr.yml").read_text()
        self.assertIn("      ANTHROPIC_REVIEW_API_KEY: ${{ secrets.ANTHROPIC_REVIEW_API_KEY }}", text)

    def test_mair_681_release_journal_is_no_longer_committed(self):
        self.assertFalse((REPO / "RELEASE_JOURNAL.md").exists())


if __name__ == "__main__":
    unittest.main()
