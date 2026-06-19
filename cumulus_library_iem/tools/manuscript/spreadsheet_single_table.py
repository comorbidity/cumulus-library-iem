#!/usr/bin/env python3
"""
Build a tier-pivoted code CSV from the per-disease value-set spreadsheets.

Run this inside the spreadsheet/ folder that holds the dx_*.csv value sets
(each shaped: system,code,display,tier). It writes one row per disease, with the
codes split across tier1 / tier2 / tier3 columns.

Output columns:
    disease_name, tier1_codes, tier2_codes, tier3_codes

Vocabularies included (anything else -- e.g. NCIt, MONDO -- is skipped):
    ICD-10-CM, ICD-9-CM, SNOMED CT, HPO, Orphanet

Because each tier cell mixes vocabularies, every code is prefixed with its
system (ICD10:, ICD9:, SNOMED:, HP:, ORPHA:) so SNOMED and Orphanet integers
stay distinguishable. Within a cell, codes are grouped by system in that order
and de-duplicated. Note: the dx_*.csv pattern also matches dx_iem_generic.csv
(the broad catch-all); delete that row afterward if you want specific diseases
only, or narrow --glob.

Usage:
    python build_tier_codes.py                       # scans ./, writes ./iem_codes_by_tier.csv
    python build_tier_codes.py /path/to/spreadsheet -o out.csv
"""
import argparse
import csv
import glob
import os
import sys

# code-system URI -> short tag
SYSTEMS = {
    "http://hl7.org/fhir/sid/icd-10-cm": "ICD10",
    "http://hl7.org/fhir/sid/icd-9-cm": "ICD9",
    "http://snomed.info/sct": "SNOMED",
    # "http://human-phenotype-ontology.org": "HP",
    # "http://www.orpha.net/ontology/orphanet.owl": "ORPHA",
}
SYSTEM_ORDER = ["ICD10", "ICD9", "SNOMED", "HP", "ORPHA"]  # grouping order within a cell
RANK = {tag: i for i, tag in enumerate(SYSTEM_ORDER)}
TIERS = ["1", "2", "3"]


def format_code(tag, code):
    """Prefix a code with its system so mixed-vocabulary cells stay unambiguous."""
    if tag == "HP":
        return code                  # HPO codes already look like HP:0001943
    if tag == "ORPHA":
        return "ORPHA:" + code       # Orphanet is stored bare -> normalize to ORPHA:NNN
    return f"{tag}:{code}"           # ICD10:E74.01, ICD9:271.0, SNOMED:444707001


def normalize_tier(value):
    """Return '1'/'2'/'3' from values like '1', ' 2 ', or '3.0'; else the stripped value."""
    v = (value or "").strip()
    try:
        return str(int(float(v)))
    except ValueError:
        return v


def build_row(path):
    disease = os.path.splitext(os.path.basename(path))[0]
    buckets = {t: [] for t in TIERS}
    other_tiers = set()
    with open(path, newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        missing = {"system", "code", "tier"} - set(reader.fieldnames or [])
        if missing:
            sys.stderr.write(f"  ! skipping {os.path.basename(path)}: missing columns {sorted(missing)}\n")
            return None
        for r in reader:
            tag = SYSTEMS.get((r.get("system") or "").strip())
            if not tag:                              # skip NCIt, MONDO, anything else
                continue
            tier = normalize_tier(r.get("tier"))
            if tier in buckets:
                buckets[tier].append((RANK[tag], format_code(tag, (r.get("code") or "").strip())))
            else:
                other_tiers.add(tier)
    if other_tiers:
        sys.stderr.write(f"  ! {os.path.basename(path)}: ignoring rows with tier(s) {sorted(other_tiers)}\n")

    def cell(items):
        items.sort(key=lambda x: x[0])               # stable sort keeps file order within a system
        return "; ".join(dict.fromkeys(code for _, code in items))

    return {
        "disease_name": disease,
        "tier1_codes": cell(buckets["1"]),
        "tier2_codes": cell(buckets["2"]),
        "tier3_codes": cell(buckets["3"]),
    }


def main():
    ap = argparse.ArgumentParser(description="Pivot per-disease value sets into tier1/2/3 code columns.")
    ap.add_argument("directory", nargs="?", default=".",
                    help="folder with dx_*.csv value sets (default: current dir)")
    ap.add_argument("-o", "--output", default="iem_codes_by_tier.csv", help="output CSV path")
    ap.add_argument("--glob", default="dx_*.csv", help="filename pattern to scan (default: dx_*.csv)")
    args = ap.parse_args()

    paths = sorted(glob.glob(os.path.join(args.directory, args.glob)))
    if not paths:
        sys.exit(f"No files matching {args.glob!r} in {os.path.abspath(args.directory)}")

    fields = ["disease_name", "tier1_codes", "tier2_codes", "tier3_codes"]
    rows = [r for r in (build_row(p) for p in paths) if r]

    with open(args.output, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    print(f"Wrote {args.output}  ({len(rows)} diseases from {len(paths)} files)")


if __name__ == "__main__":
    main()