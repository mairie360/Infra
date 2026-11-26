#!/usr/bin/env python3
"""Verdict of the spoofed e-mail test (.github/workflows/spoof-test.yml).

    RESEND_API_KEY=... scripts/spoof-check.py --token <token> --from-domain mairie360-eip.fr

The attack source sent one e-mail with a forged From: in --from-domain to the Resend inbox of
mairie360.fr, its subject holding --token. This script:

1. reads the DMARC record of --from-domain: it must enforce p=quarantine or p=reject;
2. waits (--timeout seconds) for the e-mail in Resend (GET /emails/receiving), then reads its
   authentication results (GET /emails/receiving/{id});
3. passes when Resend judged it dmarc=fail: a receiver applying the published policy rejects or
   quarantines it. dmarc=pass means the forged e-mail would be delivered: the test fails.

An e-mail that never arrives fails too (the source could not send, or Resend refused it): the
run must be looked at, it proves nothing. Writes a Markdown summary to --summary when given.
Standard library and `dig` only.
"""

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.resend.com"
DMARC_POLICY = re.compile(r"(?:^|;)\s*p\s*=\s*(none|quarantine|reject)\s*(?:;|$)", re.I)


def dmarc_policy(txt_records):
    """Policy of the single DMARC record among TXT answers, or an error string."""
    records = [r for r in txt_records if r.lower().startswith("v=dmarc1")]
    if len(records) != 1:
        return None, f"{len(records)} DMARC records (exactly one expected)"
    match = DMARC_POLICY.search(records[0])
    if not match:
        return None, "DMARC record without policy"
    return match.group(1).lower(), None


def lookup_txt(name):
    out = subprocess.run(["dig", "+short", "TXT", name], capture_output=True, text=True, timeout=30, check=True)
    # dig prints each record quoted, long ones split into several quoted strings.
    return ["".join(re.findall(r'"((?:[^"\\]|\\.)*)"', line)) for line in out.stdout.splitlines() if line.strip()]


def api_get(path, key):
    req = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {key}",
                                                      "User-Agent": "mairie360-spoof-test"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def find_email(token, key, timeout, interval, get=api_get, sleep=time.sleep, clock=time.monotonic):
    """Id of the received e-mail whose subject holds the token, or None after timeout."""
    deadline = clock() + timeout
    while True:
        listing = get("/emails/receiving", key)
        for item in listing.get("data", []):
            if token in (item.get("subject") or ""):
                return item["id"]
        if clock() >= deadline:
            return None
        sleep(interval)


def verdict(policy, policy_error, email):
    """(passed, [lines]) from the published policy and the received e-mail (None if not received)."""
    lines = []
    passed = True
    if policy_error:
        lines.append(f"DMARC record: {policy_error}")
        passed = False
    elif policy not in ("quarantine", "reject"):
        lines.append(f"DMARC policy p={policy}: a forged From: is delivered")
        passed = False
    else:
        lines.append(f"DMARC policy p={policy}")
    if email is None:
        lines.append("spoofed e-mail not received: the test proves nothing, look at the run")
        return False, lines
    auth = email.get("authentication") or {}
    lines.append(f"received from {email.get('from')}: spf={auth.get('spf')} dkim={auth.get('dkim')} dmarc={auth.get('dmarc')}")
    if (auth.get("dmarc") or "").lower() != "fail":
        lines.append("the forged e-mail was not judged dmarc=fail: it would be delivered")
        passed = False
    return passed, lines


def main(argv=None):
    import os

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--token", required=True)
    parser.add_argument("--from-domain", required=True)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--interval", type=int, default=30)
    parser.add_argument("--summary")
    args = parser.parse_args(argv)
    key = os.environ.get("RESEND_API_KEY")
    if not key:
        print("RESEND_API_KEY is not set", file=sys.stderr)
        return 2

    try:
        policy, policy_error = dmarc_policy(lookup_txt(f"_dmarc.{args.from_domain}"))
    except (OSError, subprocess.SubprocessError) as err:
        policy, policy_error = None, f"lookup failed ({err})"
    try:
        email_id = find_email(args.token, key, args.timeout, args.interval)
        email = api_get(f"/emails/receiving/{email_id}", key) if email_id else None
    except (OSError, urllib.error.URLError, ValueError) as err:
        print(f"Resend API: {err}", file=sys.stderr)
        return 2
    passed, lines = verdict(policy, policy_error, email)
    report = "\n".join([f"## Spoofed e-mail test: {'OK' if passed else 'FAILED'}", "",
                        f"Forged From: in `{args.from_domain}`.", ""] + [f"- {line}" for line in lines]) + "\n"
    print(report)
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as fh:
            fh.write(report)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
