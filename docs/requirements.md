# Business requirements: payment reconciliation

## Purpose
Every day the bank ledger (A) and the ERP ledger (B) should agree. This job matches the two and lists every payment that does not, so ops can fix it before month end.

## Users
- **Payment operations analysts**: work the open exceptions list every morning
- **Ops team lead**: watches exception rate and $ at risk on the dashboard
- **Finance controllers**: sign off month end once open exceptions over C$10,000 are cleared
- **Mainframe batch team**: runs the nightly z/OS job

## What counts as a match
A bank payment and an ERP payment match when all of these hold:
- same reference, counterparty and currency
- post dates within **3 days** of each other (bank posts 1 to 3 days after the ERP)
- amounts within **C$0.02** (FX rounding)

A split payment also matches: 2 or 3 bank lines with the same counterparty and reference, posted within 3 days, whose total is within C$0.02 of one ERP payment.

## Exception types

| Type | Definition |
|---|---|
| duplicate | Same amount, counterparty and reference posted more than once in one ledger. The first posting is kept, later ones are flagged |
| missing_in_b | In the bank, no ERP payment found |
| missing_in_a | In the ERP, no bank payment found |
| amount_mismatch | Same reference and counterparty within 3 days, amounts differ by more than C$0.02 |
| wrong_cpty_ref | Amount and date line up but the counterparty or the reference is different |

## Tolerances
| Setting | Value |
|---|---|
| Date window | +/- 3 days |
| Amount tolerance | C$0.02 |
| Split payment | 2 to 3 bank lines, within 3 days |

Known limit: a real mismatch of C$0.02 or less looks the same as FX rounding, so it is matched, not flagged. In the test data that is 24 of the 250 amount mismatches.

Changing a tolerance needs the ops lead's sign off and a rerun of `evaluate.py` to show detection and false positive rates before and after.

## SLA
- Nightly batch done by **06:00 ET**, the 50,000 record run must finish in under 2 minutes
- Dashboard refreshed by **07:00 ET**
- Exceptions over C$100,000 investigated same business day, everything else within 3 business days
- Quality bar: detection rate at least 95%, false positive rate under 2% on the test data set
