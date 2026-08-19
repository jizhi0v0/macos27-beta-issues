#!/usr/bin/env python3
"""Check that README.md's index and the issues/ write-ups agree.

README rows are summaries of the issue files. They get edited separately and
drift silently -- #24's Status sat at "confirmed on beta4" for over a week while
the README carried a corrected beta5 analysis, and nobody noticed until an audit.
A whole index-row block was also deleted once by a bad slice edit and only caught
by counting rows afterwards.

Checks:
  1. every README row links to an issue file that exists
  2. the status emoji in the row matches the one in the file's Status line
  3. the set of OS build ids mentioned in the row is a subset of the file's
     (a row may summarise; it must not claim a build the write-up never tested)
  4. every issues/*.md is referenced somewhere in README.md (a row, or prose
     such as the notification-taxonomy pointer -- not every write-up owns a row)
  5. row count, so a destructive edit cannot pass quietly

Rows for externally-reported issues with no write-up of their own are skipped for
2 and 3; they are listed so the skip is visible.

  usage: python3 tools/check-consistency.py [--expect-rows N]
  exit 0 = consistent, 1 = problems found
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EMOJI = re.compile(r'[🔴🟡🟢⚪]')
BUILD = re.compile(r'\b(2\d[A-Z]\d{3,4}[a-z])\b')   # e.g. 26A5406e, 27A5237l

def emoji(t):
    m = EMOJI.search(t or '')
    return m.group(0) if m else None

def load_rows(readme):
    rows = []
    for line in readme.splitlines():
        if not line.startswith('| ['):
            continue
        num = re.match(r'\| \[(\d+)\]', line).group(1)
        cells = line.split(' | ')
        status = cells[3] if len(cells) > 3 else ''
        link = re.search(r'\]\((issues/[^)]+\.md)\)', line)
        rows.append({'num': num, 'line': line, 'status': status,
                     'file': link.group(1) if link else None})
    return rows

def main():
    expect = None
    if '--expect-rows' in sys.argv:
        expect = int(sys.argv[sys.argv.index('--expect-rows') + 1])

    readme = open(os.path.join(ROOT, 'README.md')).read()
    rows = load_rows(readme)
    problems, skipped, referenced = [], [], set()

    print(f"index rows: {len(rows)}")
    if expect is not None and len(rows) != expect:
        problems.append(f"row count is {len(rows)}, expected {expect} -- rows may have been deleted")

    for r in rows:
        n, f = r['num'], r['file']
        if not f:
            skipped.append(f"#{n} (no issue file linked -- external report?)")
            continue
        path = os.path.join(ROOT, f)
        if not os.path.exists(path):
            problems.append(f"#{n}: linked file missing: {f}")
            continue
        referenced.add(f)
        body = open(path).read()

        # A row whose own title does not link into issues/ is an external report
        # that merely cites another issue's file; do not compare it against that
        # file's status.
        title_link = re.search(r'\| \[[^\]]+\]\((issues/[^)]+\.md)\)', r['line'])
        if not title_link or title_link.group(1) != f:
            skipped.append(f"#{n} (row cites {os.path.basename(f)} but has no write-up of its own)")
            continue

        sm = re.search(r'\| \*\*Status\*\* \|([^\n]*)', body)
        re_, ie_ = emoji(r['status']), emoji(sm.group(1) if sm else '')
        if re_ != ie_:
            problems.append(f"#{n}: status emoji README={re_} issue={ie_}  ({os.path.basename(f)})")

        rb, ib = set(BUILD.findall(r['status'])), set(BUILD.findall(body))
        only_readme = rb - ib
        if only_readme:
            problems.append(f"#{n}: README cites builds the write-up never mentions: "
                            f"{', '.join(sorted(only_readme))}  ({os.path.basename(f)})")

    # Reference can be from prose, not just a row: the notification taxonomy is
    # linked from the index preamble and owns no row of its own.
    issues_dir = os.path.join(ROOT, 'issues')
    for fn in sorted(os.listdir(issues_dir)):
        if fn.endswith('.md') and f'issues/{fn}' not in readme:
            problems.append(f"issues/{fn} is not referenced anywhere in README.md")

    if skipped:
        print("\nskipped (no own write-up):")
        for s in skipped:
            print(f"  - {s}")

    if problems:
        print(f"\n{len(problems)} problem(s):")
        for p in problems:
            print(f"  ✗ {p}")
        return 1
    print("\nconsistent ✅")
    return 0

sys.exit(main())
