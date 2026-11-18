#!/usr/bin/env bash
# runs the same cobol job locally with gnucobol, unix sort stands in for dfsort
set -euo pipefail
cd "$(dirname "$0")/.."
W=mainframe/work
mkdir -p $W

python3 mainframe/export_fixed.py data/ledger_a.csv $W/LEDGERA.txt
python3 mainframe/export_fixed.py data/ledger_b.csv $W/LEDGERB.txt

cobc -x -I mainframe -o $W/recon mainframe/RECON.cbl

start=$(date +%s.%N)
for L in A B; do
  # same keys as the jcl: ref 75-90, date 11-18, id 1-10
  LC_ALL=C sort -k1.75,1.90 -k1.11,1.18 -k1.1,1.10 $W/LEDGER$L.txt | tr -d '\n' > $W/LEDGER$L.SORTED
done
export DD_LEDGERA=$W/LEDGERA.SORTED DD_LEDGERB=$W/LEDGERB.SORTED
export DD_MATCHED=$W/MATCHED DD_UNMATCHA=$W/UNMATCHA DD_UNMATCHB=$W/UNMATCHB DD_MISMATCH=$W/MISMATCH
( time $W/recon ) 2>&1 | tee $W/report.txt
end=$(date +%s.%N)
echo "elapsed (sort + match) $(echo "$end - $start" | bc) s" | tee -a $W/report.txt
cp $W/report.txt results/mainframe_local_report.txt

python3 scripts/compare_counts.py
