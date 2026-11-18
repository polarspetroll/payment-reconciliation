# Record layouts

All files are fixed width, RECFM=FB. Amounts have no decimal point (implied 2 dp), so DFSORT and COBOL can read them as zoned decimal.

## Ledger record (LEDGERA, LEDGERB, UNMATCHA, UNMATCHB) LRECL=100

| Pos | Len | Field | COBOL | Example |
|---|---|---|---|---|
| 1 | 10 | payment id | PIC X(10) | BNK0000001 |
| 11 | 8 | post date YYYYMMDD | PIC X(8) | 20250701 |
| 19 | 13 | amount, cents | PIC 9(11)V99 | 0000000098665 |
| 32 | 3 | currency | PIC X(3) | CAD |
| 35 | 40 | counterparty | PIC X(40) | Anderson Jones and Reyes |
| 75 | 16 | reference | PIC X(16) | INV-85348695 |
| 91 | 7 | source system | PIC X(7) | EFT |
| 98 | 1 | reason code (outputs only) | PIC X | D |
| 99 | 2 | filler | PIC X(2) | |

Copybook: `PAYREC.cpy`. Sort key = reference (75,16) + post date (11,8) + payment id (1,10).

Reason codes on UNMATCHED and MISMATCH records:

| Code | Meaning | SQL v2 type |
|---|---|---|
| D | duplicate posting | duplicate |
| M | nothing on the other side | missing_in_b / missing_in_a |
| A | same payment, amount off by more than C$0.02 | amount_mismatch |
| C | same reference, different counterparty | wrong_cpty_ref |

## MATCHED LRECL=80

One row per matched bank line (a split payment gives 2 or 3 rows with the same ERP id).

| Pos | Len | Field |
|---|---|---|
| 1 | 10 | bank payment id |
| 11 | 10 | erp payment id |
| 21 | 16 | reference |
| 37 | 13 | bank amount, cents |
| 50 | 8 | bank post date |
| 58 | 1 | rule: W = 1 to 1 window match, S = split payment |
| 59 | 22 | filler |

## MISMATCH LRECL=101

Byte 1 = ledger (`A` or `B`), bytes 2-101 = the ledger record with its reason code (A or C).

## Why COBOL and SQL can differ

A wrong *reference* exception has two different references, so the COBOL job sees each half in a different group and writes both to UNMATCHED (reason M). SQL pairs them as `wrong_cpty_ref`. The record status (matched or exception) is the same, only the label differs. `scripts/compare_counts.py` accounts for this.

## Note on EBCDIC

References are `INV-` + 8 digits and dates and ids are letters and digits, so grouping works the same in ASCII and EBCDIC. Upload in text mode so Zowe converts the code page and each line becomes one record.
