# Results

Data: seed 42, 50,000 base payments. Ledger A (bank) 51,402 rows, ledger B (ERP) 49,829 rows, 1,200 planted exceptions (1,607 truth rows, since a mismatch has a bank side and an ERP side). Noise settings are at the top of `generate.py`. Same seed gives the same numbers every run. Raw outputs are in `results/`.

## Headline

| Metric | v1 | v2 |
|---|---|---|
| Detection rate | **91.0%** (1,092 / 1,200) | **98.0%** (1,176 / 1,200) |
| False positive rate | 87.8% (10,712 / 12,208 flagged) | **1.52%** (24 / 1,583 flagged) |
| Exceptions with the right type | n/a (v1 only says "unmatched") | 97.9% |

v1 = exact amount + reference + counterparty, post dates within 3 days, and bank lines with the same reference on the same day treated as a split payment (sum not checked).
v2 = duplicate check with `ROW_NUMBER()`, C$0.02 amount tolerance, a real split rule (2 or 3 lines within 3 days whose sum matches), then every exception gets a type.

## By exception type (detection %)

| Type | Planted | v1 | v2 |
|---|---|---|---|
| duplicate | 300 | 65.0 | 100.0 |
| missing_in_b | 250 | 100.0 | 100.0 |
| missing_in_a | 250 | 100.0 | 100.0 |
| amount_mismatch | 250 | 99.2 | 90.4 |
| wrong_cpty_ref | 150 | 99.3 | 100.0 |

Amount mismatches go down in v2 on purpose: 24 of them are only 1 or 2 cents, inside the C$0.02 tolerance that v2 needs for FX rounding.

## By source system

| Source | Exceptions | v1 detection | v2 detection | v2 FP rate |
|---|---|---|---|---|
| Card | 309 | 89.97 | 98.06 | 1.76 |
| Cheque | 166 | 86.75 | 98.80 | 2.33 |
| EFT | 525 | 92.76 | 97.52 | 1.43 |
| Wire | 200 | 91.50 | 98.50 | 0.74 |

## Miss analysis (`sql/04_miss_analysis.sql`)

| Version | Kind | Cause | Records | Exceptions |
|---|---|---|---|---|
| v1 | missed exception | split payment | 111 | 108 |
| v1 | false positive | rounding | 8,862 | |
| v1 | false positive | split payment | 1,850 | |
| v2 | missed exception | rounding | 48 | 24 |
| v2 | false positive | split payment | 20 | |
| v2 | false positive | rounding | 4 | |

What it showed and what changed:
- **v1 misses = split payments.** The same-day split shortcut swallowed duplicate postings (a copy on the same day looks like a 2-line split). v2 runs a duplicate check first and makes splits add up.
- **v1 false positives = rounding and splits.** USD payments 1 cent off from FX failed the exact amount match, and splits spread over several days were never grouped. v2 adds the C$0.02 tolerance and the split rule.
- **What v2 still gets wrong.** The 24 cent-level mismatches sit inside the tolerance. The false positives are payments made in 2 equal installments (the duplicate rule flags the second one), leftover lines of splits that had an exception on another line, and 2 USD payments converted twice (3 cents off).

## Mainframe job vs SQL

`mainframe/RECON.cbl` runs the v2 rules: one pass over both files sorted by reference, each reference group matched in memory. Output from `scripts/compare_counts.py`:

| Output | COBOL | SQL v2 | Equal |
|---|---|---|---|
| MATCHED (bank lines) | 50,530 | 50,530 | yes |
| UNMATCHED-A | 565 | 565 | yes |
| UNMATCHED-B | 404 | 404 | yes |
| MISMATCH | 614 | 614 | yes |

Record level: 101,231 records compared, 0 with a different status. The only label difference is wrong *reference* pairs, which COBOL writes as UNMATCHED because the two halves have different references (see `mainframe/LAYOUT.md`).

**Timing.** Local run with GnuCOBOL 3 + unix sort standing in for DFSORT: about 0.2 s for the COBOL step and under 0.3 s sort + match on all 101,231 records (`results/mainframe_local_report.txt`). IBM Z elapsed and CPU time: _fill in from the JES job log after running on IBM Z Xplore_ (steps in `docs/runbook.md`).

## Where each number comes from

| Number | Produced by |
|---|---|
| Row counts, 1,200 exceptions | `generate.py` output, `data/truth.csv` |
| Detection, FP rate, by type, by source | `evaluate.py v1` / `v2` -> `results/v*_summary.csv`, `v*_by_type.csv`, `v*_by_source.csv` |
| Miss analysis | `sql/04_miss_analysis.sql` -> `results/miss_analysis_v1.csv`, `_v2.csv` |
| COBOL vs SQL | `scripts/run_mainframe_local.sh` -> `results/cobol_vs_sql.md` |
| Dashboard figures (1,583 exceptions, 1.56% of records, C$11.3M at risk) | view `v_recon` in `sql/05_powerbi_views.sql`, USD at a placeholder 1.37 |
