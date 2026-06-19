#!/usr/bin/env python3
"""
Render each query in a topic/query TSV as a syntax-highlighted boolean tree.

By default the field (`note:`) is dropped entirely, leaving a clean boolean
tree of OR / AND / NOT over bare terms. To show the field instead:
  --fields-on-groups : put note: on every group node (note:OR / note:AND)
  --fields-on-leaves : put note: on every individual term

Conventions:
  - OR / AND group their children (any-of / all-of); NOT marks an excluded branch
  - quoted phrases, bare tokens, operators (and the field, when shown) are colorized

Color auto-enables on a terminal and disables when piped; force with --color,
suppress with --no-color.

Usage:
    python query_tree.py query_topics.tsv
    python query_tree.py query_topics.tsv dx_citrullinemia
    python query_tree.py query_topics.tsv --fields-on-groups
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

def col_op(s):     return c("1;35", s)   # bold magenta - operator
def col_not(s):    return c("1;31", s)   # bold red     - negation
def col_field(s):  return c("34", s)     # blue         - field prefix (when shown)
def col_phrase(s): return c("32", s)     # green        - quoted phrase
def col_bare(s):   return c("36", s)     # cyan         - bare token
def col_tree(s):   return c("90", s)     # gray         - connectors

# ---------- tokenize ----------
def tokenize(query):
    q = re.sub(r"note:\s+", "note:", query)
    tokens, i, n = [], 0, len(q)
    while i < n:
        ch = q[i]
        if ch.isspace():
            i += 1
        elif ch == '"':
            j = q.index('"', i + 1)
            tokens.append(q[i:j + 1]); i = j + 1
        elif ch in "()":
            tokens.append(ch); i += 1
        else:
            j = i
            while j < n and not q[j].isspace() and q[j] not in '()"':
                j += 1
            tokens.append(q[i:j]); i = j
    return tokens


# ---------- parse ----------
class Parser:
    def __init__(self, tokens):
        self.toks, self.i = tokens, 0
    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None
    def take(self):
        t = self.toks[self.i]; self.i += 1; return t
    def expr(self):
        operands = [self.operand()]
        ops = []
        while self.peek() in ("OR", "AND"):
            ops.append(self.take()); operands.append(self.operand())
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


# ---------- normalize ----------
def push_fields(node, inherited=None):
    """Move every field onto its leaves and strip embedded prefixes from leaf text."""
    if node["kind"] == "leaf":
        own = None
        m = re.match(r"^(note):(.+)$", node["text"])
        if m:
            own, node["text"] = "note:", m.group(2)
        node["field"] = own or node.get("field") or inherited
        return
    child_inherited = node.get("field") or inherited
    node["field"] = None
    for ch in node["children"]:
        push_fields(ch, child_inherited)

def annotate_group_fields(node):
    def leaves(n):
        if n["kind"] == "leaf":
            return {n["field"]}
        s = set()
        for ch in n["children"]:
            s |= leaves(ch)
        return s
    if node["kind"] == "group":
        lf = leaves(node)
        node["ufield"] = next(iter(lf)) if len(lf) == 1 else None
        for ch in node["children"]:
            annotate_group_fields(ch)


# ---------- render ----------
def color_term(text):
    return col_phrase(text) if text.startswith('"') else col_bare(text)

def render(node, prefix="", is_last=True, is_root=True, covered=None, fields="none"):
    neg = col_not("NOT ") if node.get("negated") else ""
    if node["kind"] == "group":
        if fields == "groups":
            uf = node.get("ufield")
            fld = col_field(uf) if uf is not None else ""
            new_covered = uf if uf is not None else covered
        else:
            fld, new_covered = "", covered
        label = neg + fld + col_op(node["op"])
    else:
        f = node.get("field")
        fld = col_field(f) if (fields == "leaves" and f) else ""
        label = neg + fld + color_term(node["text"])
        new_covered = covered

    if is_root:
        lines = [label]
        child_prefix = ""
    else:
        lines = [prefix + col_tree("└── " if is_last else "├── ") + label]
        child_prefix = prefix + ("    " if is_last else col_tree("│") + "   ")

    if node["kind"] == "group":
        kids = node["children"]
        for idx, kid in enumerate(kids):
            lines += render(kid, child_prefix, idx == len(kids) - 1, False, new_covered, fields)
    return lines

def tree(query, fields="none"):
    ast = Parser(tokenize(query)).expr()
    push_fields(ast)
    annotate_group_fields(ast)
    return "\n".join(render(ast, fields=fields))


# ---------- main ----------
def main(argv):
    global USE_COLOR
    flags = {a for a in argv[1:] if a.startswith("--")}
    pos = [a for a in argv[1:] if not a.startswith("--")]
    USE_COLOR = ("--color" in flags) or (sys.stdout.isatty() and "--no-color" not in flags)
    fields = "groups" if "--fields-on-groups" in flags else ("leaves" if "--fields-on-leaves" in flags else "none")

    path = pos[0] if pos else "query_topics.tsv"
    only = pos[1] if len(pos) > 1 else None

    for topic, query in read_tsv(path):
        if only and topic != only:
            continue
        print(col_op("━" * 70)); print(topic); print(col_op("━" * 70))
        try:
            print(tree(query, fields))
        except Exception as e:
            print(f"(could not parse: {e})"); print(query)
        print()


if __name__ == "__main__":
    main(sys.argv)