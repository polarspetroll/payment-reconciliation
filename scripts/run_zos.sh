#!/usr/bin/env bash
# run the batch job on ibm z xplore with zowe cli
# set ZOWE_OPT_USER and the zowe pass env var first, change /z/z68330 in RECONZX.jcl to your id
set -e
U=$ZOWE_OPT_USER
H=/z/$(echo $U | tr A-Z a-z)
python3 mainframe/export_fixed.py data/ledger_a.csv /tmp/LEDGERA.txt
python3 mainframe/export_fixed.py data/ledger_b.csv /tmp/LEDGERB.txt
# first time only, makes CBL CPY LOAD libraries
zowe jobs submit local-file mainframe/ALLOC.jcl --wait-for-output || true
zowe files upload file-to-uss /tmp/LEDGERA.txt $H/LEDGERA.txt
zowe files upload file-to-uss /tmp/LEDGERB.txt $H/LEDGERB.txt
zowe files upload file-to-data-set mainframe/RECON.cbl "$U.CBL(RECON)"
zowe files upload file-to-data-set mainframe/PAYREC.cpy "$U.CPY(PAYREC)"
zowe jobs submit local-file mainframe/COMPILE.jcl --wait-for-output
zowe jobs submit local-file mainframe/RECONZX.jcl --wait-for-output
