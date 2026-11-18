import os
import psycopg

DSN = os.getenv("RECON_DSN", "postgresql://postgres:postgres@localhost:5432/recon")


def main():
    with psycopg.connect(DSN) as conn:
        conn.execute(open("sql/01_schema.sql").read())
        with conn.cursor() as cur:
            for table, path in [("ledger_a", "data/ledger_a.csv"), ("ledger_b", "data/ledger_b.csv"), ("truth", "data/truth.csv")]:
                with open(path) as f, cur.copy(f"copy {table} from stdin with (format csv, header true)") as cp:
                    cp.write(f.read())
                cur.execute(f"select count(*) from {table}")
                print(table, cur.fetchone()[0])
        conn.execute("analyze")


if __name__ == "__main__":
    main()
