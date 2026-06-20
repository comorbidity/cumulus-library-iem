#!/usr/bin/env python3
"""
build_iem_rx_valuesets.py
=========================
Generate per-IEM medication value sets (RxNorm + ATC) with specificity tiers.

Design / provenance
--------------------
* Drug-to-disease assignment and TIER are clinical curation (see CURATION below).
* ATC codes are embedded from the WHO Collaborating Centre ATC/DDD Index
  (atcddd.fhi.no, index "Last updated 2026-01-20") and verified drug-by-drug.
  Nothing here is recalled-from-memory; every ATC code was source-checked.
* RxNorm RxCUIs are NOT hardcoded. RxCUIs are numeric and brittle to recall,
  so they are resolved at runtime from the NLM RxNav API (authoritative source).
  Run this where rxnav.nlm.nih.gov is reachable to fill them in.
  RxNav also returns the ingredient's ATC membership, which this script uses to
  CROSS-CHECK the embedded ATC codes and flag any mismatch.

Tier definitions (per request)
  1 = best match, highest specificity, indicated ONLY for this IEM
  2 = high specificity for this IEM but also indicated for other IEM(s)
  3 = low specificity for this IEM but a known treatment for this IEM

Usage
  python3 build_iem_rx_valuesets.py --outdir ./out
  (no third-party deps; stdlib only)
"""
from __future__ import annotations
import argparse, csv, json, os, sys, time
import urllib.request, urllib.parse, urllib.error

RXNORM_SYS = "http://www.nlm.nih.gov/research/umls/rxnorm"
ATC_SYS    = "http://www.whocc.no/atc"
RXNAV      = "https://rxnav.nlm.nih.gov/REST"

# ---------------------------------------------------------------------------
# Verified ATC map  (ingredient key -> ATC code)  -- source: WHOCC ATC/DDD Index
# None  => no clean single-ingredient ATC for the IEM indication; RxNorm only.
# ---------------------------------------------------------------------------
ATC = {
    "chenodeoxycholic acid":                 "A05AA01",
    "cholic acid":                           "A05AA03",
    "levocarnitine":                         "A16AA01",
    "carglumic acid":                        "A16AA05",
    "betaine":                               "A16AA06",
    "imiglucerase":                          "A16AB02",
    "alglucerase":                           "A16AB01",
    "alglucosidase alfa":                    "A16AB07",
    "velaglucerase alfa":                    "A16AB10",
    "taliglucerase alfa":                    "A16AB11",
    "pegvaliase":                            "A16AB19",
    "avalglucosidase alfa":                  "A16AB22",
    "cipaglucosidase alfa":                  "A16AB23",
    "olipudase alfa":                        "A16AB25",
    "sodium phenylbutyrate":                 "A16AX03",
    "nitisinone":                            "A16AX04",
    "miglustat":                             "A16AX06",
    "sapropterin":                           "A16AX07",
    "glycerol phenylbutyrate":               "A16AX09",
    "eliglustat":                            "A16AX10",
    "sodium benzoate":                       "A16AX11",
    "triheptanoin":                          "A16AX17",
    "fosdenopterin":                         "A16AX19",
    "sepiapterin":                           "A16AX28",
    "sodium phenylacetate and sodium benzoate": "A16AX30",
    "arimoclomol":                           "N07XX17",
    "levacetylleucine":                      "N07XX27",
    "empagliflozin":                         "A10BK03",
    "thiamine":                              "A11DA01",
    "pyridoxine":                            "A11HA02",
    "folic acid":                            "B03BB01",
    "hydroxocobalamin":                      "B03BA03",
    "allopurinol":                           "M04AA01",
    "filgrastim":                            "L03AA02",
    # ambiguous ATC for the UCD indication -> RxNorm only:
    "arginine":                              None,
    "citrulline":                            None,
}

# ---------------------------------------------------------------------------
# Curation:  disease_file -> list of (ingredient_key, tier, note)
# Diseases with no approved disease-specific pharmacotherapy -> empty list,
# with rationale in NOTES below (management is dietary / transplant).
# ---------------------------------------------------------------------------
CURATION = {
    "rx_cerebrotendinous_xanthomatosis": [
        ("chenodeoxycholic acid", 1, "Chenodal/chenodiol; primary therapy, replaces deficient bile acid"),
        ("cholic acid",           3, "alternative bile-acid; low specificity (bile-acid synthesis disorders)"),
    ],
    "rx_citrullinemia": [
        ("sodium phenylbutyrate",                 2, "nitrogen scavenger (UCD class)"),
        ("glycerol phenylbutyrate",               2, "nitrogen scavenger (UCD class)"),
        ("sodium phenylacetate and sodium benzoate", 2, "IV scavenger (Ammonul) for hyperammonemic crisis"),
        ("sodium benzoate",                       2, "nitrogen scavenger (UCD class)"),
        ("arginine",                              2, "distal UCD: arginine supplementation indicated"),
    ],
    "rx_cps1_deficiency": [
        ("sodium phenylbutyrate",                 2, "nitrogen scavenger (UCD class)"),
        ("glycerol phenylbutyrate",               2, "nitrogen scavenger (UCD class)"),
        ("sodium phenylacetate and sodium benzoate", 2, "IV scavenger (Ammonul) for hyperammonemic crisis"),
        ("sodium benzoate",                       2, "nitrogen scavenger (UCD class)"),
        ("citrulline",                            2, "proximal UCD: citrulline supplementation"),
        ("arginine",                              2, "proximal UCD: arginine supplementation"),
    ],
    "rx_cpt1_deficiency": [
        ("triheptanoin", 2, "Dojolvi; approved for LC-FAOD class (incl. CPT1A)"),
    ],
    "rx_galactosemia": [],  # dietary (galactose restriction); govorestat = investigational, not approved
    "rx_gaucher_disease": [
        ("imiglucerase",        1, "ERT, Gaucher-specific"),
        ("velaglucerase alfa",  1, "ERT, Gaucher-specific"),
        ("taliglucerase alfa",  1, "ERT, Gaucher-specific"),
        ("alglucerase",         1, "ERT, Gaucher-specific (historical/withdrawn; retained for legacy EHR)"),
        ("eliglustat",          1, "SRT, Gaucher type 1-specific"),
        ("miglustat",           2, "SRT; also Niemann-Pick type C"),
    ],
    "rx_glycogen_storage_disease_type_1": [
        ("empagliflozin", 3, "GSD Ib neutropenia (off-label SGLT2i); low specificity"),
        ("filgrastim",    3, "GSD Ib neutropenia; low specificity"),
        ("allopurinol",   3, "hyperuricemia in GSD I; low specificity"),
    ],
    "rx_glycogen_storage_disease_type_2": [
        ("alglucosidase alfa",   1, "ERT, Pompe-specific"),
        ("avalglucosidase alfa", 1, "ERT, Pompe-specific"),
        ("cipaglucosidase alfa", 1, "ERT, Pompe-specific (with miglustat stabilizer)"),
        ("miglustat",            2, "enzyme stabilizer (Opfolda) co-administered; also Gaucher/NPC"),
    ],
    "rx_glycogen_storage_disease_type_3": [],  # dietary (high-protein, cornstarch)
    "rx_glycogen_storage_disease_type_4": [],  # supportive; liver transplant
    "rx_homocystinuria": [
        ("betaine",          1, "Cystadane; remethylation therapy for homocystinuria"),
        ("pyridoxine",       3, "B6-responsive CBS deficiency; generic cofactor"),
        ("folic acid",       3, "remethylation adjunct; generic"),
        ("hydroxocobalamin", 3, "remethylation adjunct; generic"),
    ],
    "rx_maple_syrup_urine_disease": [
        ("thiamine", 3, "thiamine-responsive MSUD; generic cofactor"),
    ],
    "rx_molybdenum_cofactor_deficiency": [
        ("fosdenopterin", 1, "Nulibry; cPMP replacement, MoCD type A-specific"),
    ],
    "rx_nags_deficiency": [
        ("carglumic acid",                        1, "Carbaglu; NAGS replacement (N-carbamylglutamate)"),
        ("sodium phenylbutyrate",                 2, "scavenger adjunct in crises (UCD class)"),
        ("glycerol phenylbutyrate",               2, "scavenger adjunct (UCD class)"),
        ("sodium phenylacetate and sodium benzoate", 2, "IV scavenger (Ammonul)"),
        ("sodium benzoate",                       2, "scavenger adjunct (UCD class)"),
    ],
    "rx_niemann_pick_disease": [
        ("olipudase alfa",    1, "Xenpozyme; ERT for ASMD (type A/B)"),
        ("arimoclomol",       1, "Miplyffa; NPC-specific"),
        ("levacetylleucine",  1, "Aqneursa; NPC neurological manifestations"),
        ("miglustat",         2, "NPC (substrate reduction); also Gaucher"),
    ],
    "rx_ornithine_transcarbamylase": [
        ("sodium phenylbutyrate",                 2, "nitrogen scavenger (UCD class)"),
        ("glycerol phenylbutyrate",               2, "nitrogen scavenger (UCD class)"),
        ("sodium phenylacetate and sodium benzoate", 2, "IV scavenger (Ammonul) for hyperammonemic crisis"),
        ("sodium benzoate",                       2, "nitrogen scavenger (UCD class)"),
        ("citrulline",                            2, "proximal UCD: citrulline supplementation"),
        ("arginine",                              2, "proximal UCD: arginine supplementation"),
    ],
    "rx_phenylketonuria": [
        ("pegvaliase",  1, "Palynziq; PEG-PAL, PKU-specific"),
        ("sapropterin", 2, "Kuvan; BH4, also used in BH4-deficiency"),
        ("sepiapterin", 2, "Sephience; BH4 precursor, also BH4-deficiency"),
    ],
    "rx_tyrosinemia_type_1": [
        ("nitisinone", 1, "Orfadin/Nityr; HT-1 primary therapy (NB: also EU alkaptonuria indication)"),
    ],
    "rx_urea_cycle_disorders": [
        ("sodium phenylbutyrate",                 1, "Buphenyl/Pheburane; labeled for UCD"),
        ("glycerol phenylbutyrate",               1, "Ravicti; labeled for UCD"),
        ("sodium phenylacetate and sodium benzoate", 1, "Ammonul; IV for acute hyperammonemia in UCD"),
        ("sodium benzoate",                       1, "nitrogen scavenger for UCD hyperammonemia"),
        ("carglumic acid",                        2, "Carbaglu; NAGS deficiency (a UCD subtype)"),
        ("arginine",                              2, "UCD-subtype-dependent supplementation"),
        ("citrulline",                            2, "proximal UCD supplementation"),
    ],
}

NOTES = {
    "rx_galactosemia": "No FDA-approved disease-specific drug. Management is dietary "
                       "(galactose/lactose restriction). govorestat (AT-007, ATC A16AX24) "
                       "is investigational for classic galactosemia and is intentionally excluded.",
    "rx_glycogen_storage_disease_type_3": "No disease-specific pharmacotherapy. Management is "
                       "dietary (high-protein diet, uncooked cornstarch).",
    "rx_glycogen_storage_disease_type_4": "No disease-specific pharmacotherapy. Supportive care; "
                       "liver transplantation for progressive hepatic/cirrhotic disease.",
    "rx_maple_syrup_urine_disease": "Dietary BCAA restriction is the mainstay; thiamine helps only "
                       "the thiamine-responsive subtype. Sodium phenylbutyrate is investigational.",
    "rx_cpt1_deficiency": "Mainstay is dietary (fasting avoidance, low-LCT/high-carb, MCT). "
                       "Carnitine supplementation is generally NOT indicated in CPT1A (carnitine "
                       "is typically normal/high) and is excluded.",
}

# ---------------------------------------------------------------------------
# Display names for output (ingredient -> human display)
# ---------------------------------------------------------------------------
DISPLAY = {k: k for k in ATC}
DISPLAY.update({
    "sodium phenylacetate and sodium benzoate": "sodium phenylacetate / sodium benzoate",
})

# ---------------------------------------------------------------------------
# RxNav resolution
# ---------------------------------------------------------------------------
def _get(url, timeout=15):
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))

def resolve_rxcui(name):
    """Return (rxcui, rxnorm_name) for an ingredient name, or (None, None)."""
    q = urllib.parse.quote(name)
    # exact/normalized ingredient lookup
    data = _get(f"{RXNAV}/rxcui.json?name={q}&search=2")
    ids = (data.get("idGroup") or {}).get("rxnormId") or []
    if not ids:
        # fallback: approximate match, take best candidate
        data = _get(f"{RXNAV}/approximateTerm.json?term={q}&maxEntries=1")
        cand = (data.get("approximateGroup") or {}).get("candidate") or []
        if cand:
            ids = [cand[0].get("rxcui")]
    if not ids:
        return None, None
    rxcui = ids[0]
    nm = _get(f"{RXNAV}/rxcui/{rxcui}/property.json?propName=RxNorm%20Name")
    props = (nm.get("propConceptGroup") or {}).get("propConcept") or []
    rxname = props[0]["propValue"] if props else name
    return rxcui, rxname

def rxnav_atc(rxcui):
    """Return set of ATC classIds RxNav associates with this rxcui."""
    try:
        data = _get(f"{RXNAV}/rxclass/class/byRxcui.json?rxcui={rxcui}&relaSource=ATC")
    except Exception:
        return set()
    out = set()
    for it in (data.get("rxclassDrugInfoList") or {}).get("rxclassDrugInfo", []) or []:
        cid = (it.get("rxclassMinConceptItem") or {}).get("classId")
        if cid:
            out.add(cid)
    return out

# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="./iem_rx_valuesets")
    ap.add_argument("--no-rxnav", action="store_true",
                    help="skip RxNav (ATC-only output; RxNorm codes left UNRESOLVED)")
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    # cache resolutions across diseases
    rxcache, atc_flags, online = {}, [], not args.no_rxnav
    if online:
        try:
            _get(f"{RXNAV}/version.json", timeout=8)
        except Exception as e:
            online = False
            print(f"[warn] RxNav unreachable ({e.__class__.__name__}); "
                  f"RxNorm codes will be UNRESOLVED. ATC rows are still emitted.",
                  file=sys.stderr)

    def resolve(ing):
        if ing in rxcache:
            return rxcache[ing]
        rxcui, rxname = (None, None)
        if online:
            try:
                rxcui, rxname = resolve_rxcui(ing)
                if rxcui and ing in ATC and ATC[ing]:
                    got = rxnav_atc(rxcui)
                    if got and ATC[ing] not in got:
                        atc_flags.append((ing, ATC[ing], sorted(got)))
                time.sleep(0.05)
            except Exception as e:
                print(f"[warn] resolve {ing!r}: {e}", file=sys.stderr)
        rxcache[ing] = (rxcui, rxname)
        return rxcache[ing]

    combined = []
    for disease, drugs in CURATION.items():
        rows = []
        for ing, tier, _note in drugs:
            disp = DISPLAY.get(ing, ing)
            rxcui, rxname = resolve(ing)
            rows.append([RXNORM_SYS, rxcui or "UNRESOLVED", rxname or disp, tier])
            if ATC.get(ing):
                rows.append([ATC_SYS, ATC[ing], disp, tier])
        # write per-disease csv (exact requested filename)
        path = os.path.join(args.outdir, f"{disease}.csv")
        with open(path, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["system", "code", "display", "tier"])
            w.writerows(rows)
        for r in rows:
            combined.append([disease] + r)
        tag = "" if drugs else "  (no approved drug-specific therapy; see notes)"
        print(f"  {disease:<42} {len(rows):>2} rows{tag}")

    with open(os.path.join(args.outdir, "_ALL_iem_rx_valuesets.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["disease", "system", "code", "display", "tier"])
        w.writerows(combined)
    with open(os.path.join(args.outdir, "_NOTES.json"), "w") as f:
        json.dump(NOTES, f, indent=2)

    if atc_flags:
        print("\n[ATC cross-check mismatches vs RxNav]")
        for ing, mine, got in atc_flags:
            print(f"  {ing}: embedded {mine} not in RxNav {got}")
    print(f"\nRxNav: {'ONLINE' if online else 'OFFLINE (RxNorm UNRESOLVED)'}. "
          f"Output -> {args.outdir}")

if __name__ == "__main__":
    main()