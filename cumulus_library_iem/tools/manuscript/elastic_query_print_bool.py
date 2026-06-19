#!/usr/bin/env python3
"""
Pretty-print the queries in a topic/query TSV so a human can see the
parenthesis nesting.

Each query is a single-line Lucene `query_string`; this re-expands it across
many indented lines:
  - one indent level per '('
  - each term on its own line
  - operators (OR / AND / NOT) kept at the end of the preceding line
  - field prefixes (note:) stay attached to their group, e.g. `note:(`

Usage:
    python pretty_print_queries.py query_topics.tsv
    python pretty_print_queries.py query_topics.tsv dx_citrullinemia   # one topic
"""

import re
import sys
from pathlib import Path
from cumulus_library_iem.tools import filetool

INDENT = "  "
OPERATORS = {"OR", "AND", "NOT"}


def read_tsv(path):
    """Yield (topic, query) pairs, skipping the header row."""
    if not isinstance(path, Path):
        path = Path(filetool.path_spreadsheet(path))

    with open(path, encoding="utf-8") as fh:
        next(fh, None)  # header: topic<TAB>query
        for line in fh:
            line = line.rstrip("\n")
            if line:
                topic, _, query = line.partition("\t")
                yield topic, query


def tokenize(query):
    """Split a query into tokens: '(' , ')' , quoted phrases, and bare words."""
    # glue a field prefix to what follows: 'note: x' -> 'note:x'
    q = re.sub(r"note:\s+", "note:", query)
    tokens, i, n = [], 0, len(q)
    while i < n:
        c = q[i]
        if c.isspace():
            i += 1
        elif c == '"':                       # quoted phrase (kept whole, with quotes)
            j = q.index('"', i + 1)
            tokens.append(q[i:j + 1])
            i = j + 1
        elif c in "()":
            tokens.append(c)
            i += 1
        else:                                # a bare word (term, operator, or 'note:')
            j = i
            while j < n and not q[j].isspace() and q[j] not in '()"':
                j += 1
            tokens.append(q[i:j])
            i = j
    return tokens


def pretty(query):
    lines, depth, pending = [], 0, ""
    for tok in tokenize(query):
        if tok == "(":
            lines.append(INDENT * depth + pending + "(")
            pending = ""
            depth += 1
        elif tok == ")":
            depth = max(depth - 1, 0)
            lines.append(INDENT * depth + ")")
        elif tok in OPERATORS:
            if lines:                        # attach operator to the previous line
                lines[-1] += " " + tok
            else:
                lines.append(INDENT * depth + tok)
        elif tok.endswith(":"):              # a field prefix like 'note:' before a '('
            pending = tok
        else:                                # a term (quoted phrase or bare token)
            lines.append(INDENT * depth + tok)
    return "\n".join(lines)


def main(argv):
    path = argv[1] if len(argv) > 1 else "query_topics.tsv"
    only = argv[2] if len(argv) > 2 else None
    for topic, query in read_tsv(path):
        if only and topic != only:
            continue
        print("=" * 70)
        print(topic)
        print("=" * 70)
        print(pretty(query))
        print()


if __name__ == "__main__":
    main(sys.argv)
