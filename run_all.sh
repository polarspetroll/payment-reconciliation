#!/usr/bin/env bash
# full pipeline, generate -> rules -> scoring -> cobol check -> charts
set -euo pipefail
export PGPASSWORD=${PGPASSWORD:-postgres}
PSQL="psql -h localhost -U postgres -d recon -q"

python3 generate.py
python3 load.py

$PSQL -f sql/02_rules_v1.sql
python3 evaluate.py v1
$PSQL -v tbl=recon_v1 -v out=results/miss_analysis_v1.csv -f sql/04_miss_analysis.sql

$PSQL -f sql/03_rules_v2.sql
python3 evaluate.py v2
$PSQL -v tbl=recon_v2 -v out=results/miss_analysis_v2.csv -f sql/04_miss_analysis.sql

$PSQL -f sql/05_powerbi_views.sql
$PSQL -c "\\copy (select * from v_recon_bi order by status, week_start) to 'powerbi/v_recon_bi.csv' csv header"
bash scripts/run_mainframe_local.sh
python3 scripts/make_charts.py
