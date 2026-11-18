import csv
import sys

# fixed width layout, 100 bytes. see mainframe/LAYOUT.md
def to_fixed(row):
    cents = int(round(float(row["amount"]) * 100))
    rec = (row["payment_id"].ljust(10)
           + row["post_date"].replace("-", "")
           + str(cents).zfill(13)
           + row["currency"].ljust(3)
           + row["counterparty"][:40].ljust(40)
           + row["reference"].ljust(16)
           + row["source_system"].ljust(7)
           + "   ")
    assert len(rec) == 100, rec
    return rec


def main(src, dst):
    n = 0
    with open(src) as f, open(dst, "w", encoding="ascii", errors="replace") as out:
        for row in csv.DictReader(f):
            out.write(to_fixed(row) + "\n")
            n += 1
    print(dst, n, "records")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
