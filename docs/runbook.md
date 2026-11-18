# Runbook

## Inputs
| Input | Where |
|---|---|
| Bank ledger | `data/ledger_a.csv`, on z/OS `<userid>.RECON.LEDGERA` (FB 100) |
| ERP ledger | `data/ledger_b.csv`, on z/OS `<userid>.RECON.LEDGERB` (FB 100) |
| Answer key (test only) | `data/truth.csv` |
| Layouts | `mainframe/LAYOUT.md`, `mainframe/PAYREC.cpy` |

## Rerun the SQL side
```bash
docker compose up -d          # postgres 16
./run_all.sh                  # generate, load, v1, v2, evaluate, miss analysis, cobol check, charts
```
Single steps: `psql -h localhost -U postgres -d recon -f sql/03_rules_v2.sql` then `python evaluate.py v2`. The rule scripts drop and rebuild their result table so they are safe to rerun.

## Rerun on z/OS (IBM Z Xplore + Zowe CLI)
```bash
python mainframe/export_fixed.py data/ledger_a.csv LEDGERA.txt
python mainframe/export_fixed.py data/ledger_b.csv LEDGERB.txt

zowe zos-files create data-set-sequential "Z00000.RECON.LEDGERA" --record-format FB --record-length 100 --size 10CYL
zowe zos-files create data-set-sequential "Z00000.RECON.LEDGERB" --record-format FB --record-length 100 --size 10CYL
zowe zos-files upload file-to-data-set LEDGERA.txt "Z00000.RECON.LEDGERA"
zowe zos-files upload file-to-data-set LEDGERB.txt "Z00000.RECON.LEDGERB"

zowe zos-files upload file-to-data-set mainframe/RECON.cbl "Z00000.CBL(RECON)"
zowe zos-files upload file-to-data-set mainframe/PAYREC.cpy "Z00000.CPY(PAYREC)"
zowe zos-jobs submit local-file mainframe/COMPILE.jcl --view-all-spool-content
zowe zos-jobs submit local-file mainframe/RECONJOB.jcl --view-all-spool-content
```
Replace `Z00000` with your userid. The CLEANUP step deletes the old outputs so the job can be resubmitted as is. Elapsed and CPU time per step are in the JES2 job log (`JESMSGLG`, look for the IEF032I/IEF033I step end messages).

On IBM Z Xplore user datasets are capped at 200 KB and must be allocated in TRK, so the 5 MB ledgers do not fit in a dataset. Use `bash scripts/run_zos.sh` instead: it allocates small CBL/CPY/LOAD libraries with `mainframe/ALLOC.jcl`, uploads the ledgers as z/OS UNIX files to your home directory and submits `mainframe/RECONZX.jcl` (z/OS UNIX sort + RECON reading the UNIX files with FILEDATA=TEXT). Change `/z/z68330` in RECONZX.jcl to your own id. A dataset allocation message `ZXP SAYS NO` means you hit that cap.

Local test without a mainframe: `bash scripts/run_mainframe_local.sh` (GnuCOBOL + unix sort). It also checks the COBOL output against SQL v2, file by file and record by record (`results/cobol_vs_sql.md`).

## Common abends

| Abend | What it means here | Fix |
|---|---|---|
| **S0C7** | Data exception, a non numeric value in `PR-AMOUNT` (usually a CSV export with a decimal point or a blank amount, or a binary upload so the digits are still ASCII) | Re-export with `export_fixed.py`, upload in text mode, find the bad record with a DFSORT step using `INCLUDE COND=(19,13,ZD,NE,NUM)` |
| **S013** | Open failed, the DCB in the JCL does not match the dataset (wrong LRECL/RECFM) or a DD is missing | Make sure the input is FB 100, outputs match the LRECLs in `RECONJOB.jcl` (80, 100, 100, 101) and all six DD names exist |
| **S806** | Program RECON not found | COMPILE job did not finish or `STEPLIB` points to the wrong load library |
| **SB37 / SD37** | Output dataset out of space | Raise the `SPACE=(CYL,...)` on the failing DD |
| JCL error, dataset already exists | Old outputs left from a failed run | The CLEANUP step handles this, or delete with `zowe zos-files delete data-set` |
| Wrong counts | Inputs not sorted by reference, so one payment's lines land in different groups | Check SORT FIELDS = ref(75,16), date(11,8), id(1,10) on both SORT steps |
| RC=16, `GROUP TOO BIG` in SYSOUT | More than 50 lines share one reference | Look at that reference in the input, raise `OCCURS 50` in RECON.cbl if it is real |
