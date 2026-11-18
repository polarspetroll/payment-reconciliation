import os
import sys
import pandas as pd
import psycopg

DSN = os.getenv("RECON_DSN", "postgresql://postgres:postgres@localhost:5432/recon")


def query(conn, sql):
    cur = conn.execute(sql)
    return pd.DataFrame(cur.fetchall(), columns=[c.name for c in cur.description])


def pct(x):
    return round(100 * x, 2)


def main(ver):
    conn = psycopg.connect(DSN)
    res = query(conn, f"""
        select r.ledger, r.payment_id, r.status, r.exception_type, x.source_system
        from recon_{ver} r
        join (select 'A' ledger, payment_id, source_system from ledger_a
              union all select 'B', payment_id, source_system from ledger_b) x
          on x.ledger = r.ledger and x.payment_id = r.payment_id""")
    truth = query(conn, "select * from truth")

    res["flagged"] = res.status != "MATCHED"
    t = truth.merge(res, left_on=["ledger", "record_id"], right_on=["ledger", "payment_id"], how="left")
    t["type_ok"] = t.flagged & (t.exception_type == t.type)

    # an exception counts as caught if any of its records got flagged
    exc = t.groupby("exception_id").agg(type=("type", "first"), source=("source_system", "first"),
                                        caught=("flagged", "any"), classified=("type_ok", "any"))

    truth_keys = set(zip(truth.ledger, truth.record_id))
    flagged = res[res.flagged].copy()
    flagged["fp"] = [k not in truth_keys for k in zip(flagged.ledger, flagged.payment_id)]

    summary = pd.DataFrame([{
        "version": ver,
        "exceptions": len(exc),
        "caught": int(exc.caught.sum()),
        "detection_pct": pct(exc.caught.mean()),
        "classified_pct": pct(exc.classified.mean()) if ver != "v1" else None,
        "flagged_records": len(flagged),
        "false_positives": int(flagged.fp.sum()),
        "fp_rate_pct": pct(flagged.fp.mean()),
    }])

    by_type = exc.groupby("type").agg(exceptions=("caught", "size"), caught=("caught", "sum"),
                                      classified=("classified", "sum")).reset_index()
    by_type["detection_pct"] = pct(by_type.caught / by_type.exceptions)
    by_type["classified_pct"] = pct(by_type.classified / by_type.exceptions)

    det_src = exc.groupby("source").agg(exceptions=("caught", "size"), caught=("caught", "sum"))
    fp_src = flagged.groupby("source_system").agg(flagged=("fp", "size"), false_positives=("fp", "sum"))
    by_src = det_src.join(fp_src).reset_index().rename(columns={"source": "source_system"})
    by_src["detection_pct"] = pct(by_src.caught / by_src.exceptions)
    by_src["fp_rate_pct"] = pct(by_src.false_positives / by_src.flagged)

    fp_type = flagged.groupby("exception_type").agg(flagged=("fp", "size"), false_positives=("fp", "sum")).reset_index()
    fp_type["fp_rate_pct"] = pct(fp_type.false_positives / fp_type.flagged)

    os.makedirs("results", exist_ok=True)
    summary.to_csv(f"results/{ver}_summary.csv", index=False)
    by_type.to_csv(f"results/{ver}_by_type.csv", index=False)
    by_src.to_csv(f"results/{ver}_by_source.csv", index=False)
    fp_type.to_csv(f"results/{ver}_flags_by_type.csv", index=False)

    print(summary.to_string(index=False), "\n")
    print(by_type.to_string(index=False), "\n")
    print(by_src.to_string(index=False), "\n")
    print(fp_type.to_string(index=False))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "v1")
