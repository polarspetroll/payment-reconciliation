import os
import pandas as pd
import psycopg

DSN = os.getenv("RECON_DSN", "postgresql://postgres:postgres@localhost:5432/recon")
W = "mainframe/work"


def chunks(path, size):
    data = open(path, "rb").read().decode("ascii")
    return [data[i:i + size] for i in range(0, len(data), size)]


# cobol side, one row per record: ledger, id, status, reason
rows = []
for r in chunks(f"{W}/MATCHED", 80):
    rows.append(("A", r[0:10], "MATCHED", ""))
    rows.append(("B", r[10:20], "MATCHED", ""))
for led, f in (("A", "UNMATCHA"), ("B", "UNMATCHB")):
    for r in chunks(f"{W}/{f}", 100):
        rows.append((led, r[0:10], "EXCEPTION", r[97]))
for r in chunks(f"{W}/MISMATCH", 101):
    rows.append((r[0], r[1:11], "EXCEPTION", r[98]))
cob = pd.DataFrame(rows, columns=["ledger", "payment_id", "status", "reason"]).drop_duplicates()

files = {
    "MATCHED (bank lines)": len(chunks(f"{W}/MATCHED", 80)),
    "UNMATCHED-A": len(chunks(f"{W}/UNMATCHA", 100)),
    "UNMATCHED-B": len(chunks(f"{W}/UNMATCHB", 100)),
    "MISMATCH": len(chunks(f"{W}/MISMATCH", 101)),
}

with psycopg.connect(DSN) as conn:
    cur = conn.execute("""
        select r.ledger, r.payment_id, r.status, r.exception_type,
               x.reference = o.reference same_ref
        from recon_v2 r
        join (select 'A' l, payment_id, reference from ledger_a union all
              select 'B', payment_id, reference from ledger_b) x on x.l = r.ledger and x.payment_id = r.payment_id
        left join (select 'A' l, payment_id, reference from ledger_a union all
                   select 'B', payment_id, reference from ledger_b) o on o.l <> r.ledger and o.payment_id = r.match_id""")
    sql = pd.DataFrame(cur.fetchall(), columns=["ledger", "payment_id", "status", "type", "same_ref"])

# a wrong reference pair spans two references, cobol sees each half alone -> unmatched
mis = sql.type.isin(["amount_mismatch"]) | ((sql.type == "wrong_cpty_ref") & (sql.same_ref == True))
sql_files = {
    "MATCHED (bank lines)": int(((sql.ledger == "A") & (sql.status == "MATCHED")).sum()),
    "UNMATCHED-A": int(((sql.ledger == "A") & (sql.status == "EXCEPTION") & ~mis).sum()),
    "UNMATCHED-B": int(((sql.ledger == "B") & (sql.status == "EXCEPTION") & ~mis).sum()),
    "MISMATCH": int((mis).sum()),
}

lines = ["| Output | COBOL | SQL v2 | Equal |", "|---|---|---|---|"]
for k in files:
    lines.append(f"| {k} | {files[k]:,} | {sql_files[k]:,} | {'yes' if files[k] == sql_files[k] else 'NO'} |")

both = sql.merge(cob, on=["ledger", "payment_id"], how="outer", suffixes=("_sql", "_cob"), indicator=True)
diff = both[(both._merge != "both") | (both.status_sql != both.status_cob)]
lines.append("")
lines.append(f"Record level: {len(both):,} records compared, {len(diff)} with a different status.")
out = "\n".join(lines)
print(out)
open("results/cobol_vs_sql.md", "w").write(out + "\n")
if len(diff):
    print(diff.head(20).to_string())
