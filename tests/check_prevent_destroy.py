#!/usr/bin/env python3
"""Every `resource` block of the repository sets `lifecycle { prevent_destroy = true }`.

Machines, buckets and secrets are imported or protected, never recreated
(MAIR-613). There is no exemption: a resource that must be deletable has to
change this check, in review.

The check reads the HCL itself (standard library only): comments and string
contents are ignored (template expressions `${...}` / `%{...}` included, with
the strings nested in them), and the setting only counts when it is an
attribute of a `lifecycle` block directly inside the resource, set to the
literal `true`. It fails closed: a file whose braces do not balance, or where
a `resource` header is not read as a block, is reported, never skipped.

    python3 tests/check_prevent_destroy.py [file.tf ...]   # default: every tracked *.tf
"""

import re
import subprocess
import sys
from pathlib import Path

# Heredoc delimiters are identifiers, which may contain hyphens.
HEREDOC = re.compile(r"<<-?([A-Za-z_][\w-]*)")
PROTECTED = re.compile(r"^\s*prevent_destroy\s*=\s*true\s*$", re.M)


def skip_string(text, i):
    """Index just past the quoted string starting at text[i] == '"'.

    Template expressions (`${...}`, `%{...}`, not the escapes `$${` / `%%{`)
    are expressions: their braces and nested strings are skipped as a whole.
    """
    n = len(text)
    i += 1
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
        elif c == '"':
            return i + 1
        elif text.startswith("$${", i) or text.startswith("%%{", i):
            i += 3
        elif text.startswith("${", i) or text.startswith("%{", i):
            i = skip_template(text, i + 2)
        else:
            i += 1
    return n


def skip_template(text, i):
    """Index just past the `}` closing a template expression whose body starts at i."""
    n = len(text)
    depth = 1
    while i < n:
        c = text[i]
        if c == '"':
            i = skip_string(text, i)
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def strip_comments_and_strings(text):
    """`text` with comments removed and string / heredoc contents blanked.

    Newlines are kept so that line numbers stay right.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "#" or text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            out.append("\n" * text.count("\n", i, end))
            i = end
        elif c == '"':
            end = skip_string(text, i)
            out.append('""' + "\n" * text.count("\n", i, end))
            i = end
        elif HEREDOC.match(text, i):
            tag = HEREDOC.match(text, i).group(1)
            line_end = text.find("\n", i)
            close = re.compile(r"^\s*" + re.escape(tag) + r"\s*$", re.M)
            m = close.search(text, line_end + 1) if line_end >= 0 else None
            end = n if m is None else m.end()
            out.append('""' + "\n" * text.count("\n", i, end))
            i = end
        else:
            out.append(c)
            i += 1
    return "".join(out)


def balanced(text):
    """The braces of `text` (comments and strings removed) all match."""
    depth = 0
    for c in text:
        depth += {"{": 1, "}": -1}.get(c, 0)
        if depth < 0:
            return False
    return depth == 0


def blocks(text, start=0, end=None):
    """[(header, body_start, body_end, line)] of the blocks directly in text[start:end]."""
    end = len(text) if end is None else end
    found = []
    depth = 0
    header_start = start
    for i in range(start, end):
        c = text[i]
        if c == "{":
            if depth == 0:
                header = text[header_start:i].strip()
                body_start = i + 1
                line = text.count("\n", 0, i) + 1
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                found.append((header, body_start, i, line))
                header_start = i + 1
        elif c == "\n" and depth == 0:
            header_start = i + 1
    return found


def lifecycle_protects(clean, start, end):
    """The body clean[start:end] has `prevent_destroy = true` as its own attribute."""
    nested = blocks(clean, start, end)
    own = list(clean[start:end])
    for _, b0, b1, _ in nested:
        for k in range(b0 - start, b1 - start):
            if own[k] != "\n":
                own[k] = " "
    return bool(PROTECTED.search("".join(own)))


def unprotected(text):
    """[(line, "type.name")] of the resources of `text` without the protection."""
    clean = strip_comments_and_strings(text)
    if not balanced(clean):
        return [(0, "(unbalanced braces once comments and strings are removed: cannot check this file)")]
    original_lines = text.split("\n")
    problems = []
    found = 0
    for header, b0, b1, line in blocks(clean):
        if not header.startswith("resource"):
            continue
        found += 1
        # Labels are blanked with the strings: read them from the original line.
        names = re.findall(r'"([^"]*)"', original_lines[line - 1])
        label = ".".join(names[:2]) or header
        ok = any(
            h.split() == ["lifecycle"] and lifecycle_protects(clean, c0, c1)
            for h, c0, c1, _ in blocks(clean, b0, b1)
        )
        if not ok:
            problems.append((line, label))
    # Every `resource` header left after cleaning must have been read as a block.
    headers = len(re.findall(r"^\s*resource\b", clean, re.M))
    if headers != found:
        problems.append((0, f"({headers} resource headers, {found} resource blocks read: cannot check this file)"))
    return problems


def tracked_tf_files(root):
    try:
        out = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "*.tf"],
            cwd=root, check=True, capture_output=True, text=True,
        ).stdout.split()
        return [root / f for f in out]
    except (OSError, subprocess.CalledProcessError):
        return [p for p in root.rglob("*.tf") if ".terraform" not in p.parts]


def main(argv):
    root = Path(__file__).resolve().parent.parent
    files = [Path(a) for a in argv] or tracked_tf_files(root)
    status = 0
    for f in sorted(files):
        for line, label in unprotected(f.read_text()):
            if line == 0:
                print(f"{f}: {label}")
            else:
                print(f"{f}:{line}: resource {label} has no lifecycle {{ prevent_destroy = true }}")
            status = 1
    print(f"{len(files)} file(s) checked, {'problems found' if status else 'every resource protected'}.")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
