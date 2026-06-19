#!/usr/bin/env python3
"""
Rewrite gene-anchored adjacency phrases in a topic/query TSV into proximity
clauses: GENE within N words of any finding keyword, EITHER order.

Two slop settings:
  * SPECIFIC (unambiguous) gene tokens  -> wider window  (SLOP_SPECIFIC)
  * COLLISION-prone short tokens        -> tighter window (SLOP_COLLISION)
    (OTC=over the counter, PAH=pulmonary arterial hypertension, ASL=arterial
     spin labeling, GALT=gut-associated lymphoid tissue, DBT, etc. -- the tight
     window limits their false-positive surface.)

Each "GENE mutation/variant/pathogenic/gene mutation" run is replaced by, for
each keyword k and order:  "GENE k"~N  OR  "k GENE"~N
Both orders at slop N give a symmetric "within N words" window (a single phrase
is asymmetric, since Lucene charges +2 for a reversed match).

Usage:
    python apply_gene_proximity.py in.tsv out.tsv
"""
import re
import sys

SLOP_SPECIFIC = 5
SLOP_COLLISION = 3

KEYWORDS = ["mutation", "mutations", "variant", "variants",
            "mutant", "pathogenic", "deletion", "duplication"]

SPECIFIC = ["ARG1", "ASS1", "BCKDHA", "BCKDHB", "CPS1", "CPT1A", "CYP27A1",
            "G6PC", "G6PC1", "GBA1", "GBE1", "GPHN", "MOCS1", "MOCS2", "MOCS3",
            "NAGS", "SLC25A13", "SLC25A15", "SLC37A4", "SMPD1"]
COLLISION = ["AGL", "ASL", "CBS", "DBT", "DLD", "FAH", "GAA", "GBA", "OTC", "PAH", "GALT"]

# keywords found in the EXISTING adjacency phrases (what we strip out)
SRC_KW = r'(?:gene mutation|mutations|mutation|variants|variant|mutant|pathogenic)'


def proximity_block(gene, slop, keywords=KEYWORDS):
    out = []
    for k in keywords:
        out.append(f'"{gene} {k}"~{slop}')
        out.append(f'"{k} {gene}"~{slop}')
    return " OR ".join(out)


def _convert_gene(q, gene, slop):
    phrase = r'"%s %s"' % (re.escape(gene), SRC_KW)
    run = phrase + r'(?:\s+OR\s+' + phrase + r')*'
    block = proximity_block(gene, slop)
    return re.subn(run, lambda m, b=block: b, q)


def convert_query(q):
    report = []
    for g in SPECIFIC:                       # process specific first (quote+space anchoring
        q, n = _convert_gene(q, g, SLOP_SPECIFIC)   # keeps GBA1 distinct from GBA, etc.)
        if n:
            report.append((g, SLOP_SPECIFIC))
    for g in COLLISION:
        q, n = _convert_gene(q, g, SLOP_COLLISION)
        if n:
            report.append((g, SLOP_COLLISION))
    return q, report


def main(argv):
    inp = argv[1] if len(argv) > 1 else "query_topics.tsv"
    out = argv[2] if len(argv) > 2 else "query_topics.tsv"

    lines = open(inp, encoding="utf-8").read().splitlines()
    header, body = lines[0], lines[1:]

    out_rows = [header]
    print(f"{'topic':42s} converted  gene(slop)")
    print("-" * 78)
    for line in body:
        if not line.strip():
            continue
        topic, _, query = line.partition("\t")
        new_query, rep = convert_query(query)
        out_rows.append(f"{topic}\t{new_query}")
        if rep:
            print(f"{topic:42s} " + ", ".join(f"{g}({s})" for g, s in rep))
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out_rows) + "\n")
    print(f"\nWrote {out}")


if __name__ == "__main__":
    main(sys.argv)
