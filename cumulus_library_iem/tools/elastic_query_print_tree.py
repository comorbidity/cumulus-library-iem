#!/usr/bin/env python3
"""
Render each query in a topic/query TSV as a syntax-highlighted boolean tree.

  - OR / AND nodes group their children (OR = any-of, AND = all-of)
  - NOT marks a negated / excluded branch
  - note: shows the field the group or term is scoped to
  - quoted phrases, bare tokens, operators, and field prefixes are colorized

Color is auto-enabled on a terminal and disabled when piped; force with
--color, suppress with --no-color.

Usage:
    python query_tree.py query_topics.tsv
    python query_tree.py query_topics.tsv dx_citrullinemia
    python query_tree.py query_topics.tsv --color | less -R
"""

import re
import sys
from cumulus_library_iem.tools.elastic_query_print_bool import read_tsv

OPERATORS = {"OR", "AND", "NOT"}
USE_COLOR = True  # set in main()


# ---------- color ----------
def c(code, s):
    return f"\033[{code}m{s}\033[0m" if USE_COLOR else s

def col_op(s):     return c("1;35", s)   # bold magenta  - boolean operator node
def col_not(s):    return c("1;31", s)   # bold red      - negation
def col_field(s):  return c("34", s)     # blue          - field prefix (note:)
def col_phrase(s): return c("32", s)     # green         - quoted phrase
def col_bare(s):   return c("36", s)     # cyan          - bare token
def col_tree(s):   return c("90", s)     # gray          - tree connectors

# ---------- tokenize ----------
def tokenize(query):
    q = re.sub(r"note:\s+", "note:", query)   # glue field prefix to its term
    tokens, i, n = [], 0, len(q)
    while i < n:
        ch = q[i]
        if ch.isspace():
            i += 1
        elif ch == '"':
            j = q.index('"', i + 1)
            tokens.append(q[i:j + 1])
            i = j + 1
        elif ch in "()":
            tokens.append(ch)
            i += 1
        else:
            j = i
            while j < n and not q[j].isspace() and q[j] not in '()"':
                j += 1
            tokens.append(q[i:j])
            i = j
    return tokens


# ---------- parse into a boolean tree ----------
class Parser:
    def __init__(self, tokens):
        self.toks, self.i = tokens, 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None

    def take(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def expr(self):
        operands = [self.operand()]
        ops = []
        while self.peek() in ("OR", "AND"):
            ops.append(self.take())
            operands.append(self.operand())
        if not ops:
            return operands[0]
        op = ops[0] if len(set(ops)) == 1 else "MIXED"
        return {"kind": "group", "op": op, "children": operands, "field": None, "negated": False}

    def operand(self):
        negated = self.peek() == "NOT"
        if negated:
            self.take()
        node = self.factor()
        node["negated"] = node.get("negated", False) or negated
        return node

    def factor(self):
        field = None
        nxt = self.peek()
        if nxt and nxt.endswith(":") and nxt not in OPERATORS:
            field = self.take()
        if self.peek() == "(":
            self.take()
            node = dict(self.expr())
            if self.peek() == ")":
                self.take()
            if field:
                node["field"] = field
            node.setdefault("negated", False)
            return node
        return {"kind": "leaf", "text": self.take(), "field": field, "negated": False}


# ---------- render ----------
def color_term(text):
    if text.startswith('"'):
        return col_phrase(text)
    if ":" in text:                       # field-prefixed bare term, e.g. note:synthase
        f, _, rest = text.partition(":")
        return col_field(f + ":") + col_bare(rest)
    return col_bare(text)

def node_label(node):
    neg = col_not("NOT ") if node.get("negated") else ""
    field = col_field(node["field"]) if node.get("field") else ""
    if node["kind"] == "leaf":
        return neg + field + color_term(node["text"])
    return neg + field + col_op(node["op"])

def render(node, prefix="", is_last=True, is_root=True):
    if is_root:
        lines = [node_label(node)]
        child_prefix = ""
    else:
        branch = "└── " if is_last else "├── "
        lines = [prefix + col_tree(branch) + node_label(node)]
        child_prefix = prefix + ("    " if is_last else col_tree("│") + "   ")
    if node.get("kind") == "group":
        kids = node["children"]
        for idx, kid in enumerate(kids):
            lines += render(kid, child_prefix, idx == len(kids) - 1, is_root=False)
    return lines


def tree(query):
    return "\n".join(render(Parser(tokenize(query)).expr()))


# ---------- main ----------
def main(argv):
    global USE_COLOR
    flags = {a for a in argv[1:] if a.startswith("--")}
    pos = [a for a in argv[1:] if not a.startswith("--")]
    USE_COLOR = ("--color" in flags) or (sys.stdout.isatty() and "--no-color" not in flags)

    path = pos[0] if pos else "query_topics.tsv"
    only = pos[1] if len(pos) > 1 else None

    for topic, query in read_tsv(path):
        if only and topic != only:
            continue
        print(col_op("━" * 70))
        print(topic)
        print(col_op("━" * 70))
        try:
            print(tree(query))
        except Exception as e:        # never crash on an odd row; show the raw query
            print(f"(could not parse: {e})")
            print(query)
        print()


if __name__ == "__main__":
    main(sys.argv)