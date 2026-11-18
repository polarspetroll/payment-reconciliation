import os
import numpy as np
import pandas as pd
from faker import Faker
from datetime import date, timedelta

SEED = 42
N = 50000
OUT = "data"

# noise settings, none of these are exceptions
LAG_P = [0.40, 0.30, 0.20, 0.10]   # bank posts 0-3 days after erp
FX_P = 0.30                        # share of usd payments off by 1 cent
SPLIT_P = 0.02                     # erp payments paid as 2-3 bank lines
EQUAL_SPLITS = 4                   # payments paid in 2 equal installments
SAME_DAY_DUP_P = 0.49              # bank double postings landing on the same day
TINY_MISMATCH = 24                 # amount mismatches of only 1-2 cents
FX_TWICE = 2                       # usd payments converted twice, 3 cents off

rng = np.random.default_rng(SEED)
fake = Faker("en_CA")
Faker.seed(SEED)

start = date(2025, 7, 1)
sources = ["Wire", "EFT", "Card", "Cheque"]
scale = {"Wire": 8.0, "EFT": 1.0, "Card": 0.15, "Cheque": 0.6}

names = set()
while len(names) < 1500:
    names.add(fake.company().replace(",", "")[:40])
cptys = sorted(names)


def lag():
    return int(rng.choice([0, 1, 2, 3], p=LAG_P))


def split_amount(total, k):
    # random unequal parts that add up exactly (in cents)
    cents = int(round(total * 100))
    while True:
        cuts = sorted(rng.choice(np.arange(100, cents - 100), k - 1, replace=False))
        parts = np.diff([0] + list(cuts) + [cents])
        if len(set(parts)) == k and min(parts) >= 100:
            return [p / 100 for p in parts]


src = rng.choice(sources, N, p=[0.15, 0.45, 0.25, 0.15])
amt = np.exp(rng.normal(7.4, 1.2, N)) * np.array([scale[s] for s in src])
base = pd.DataFrame({
    "post_date": [start + timedelta(days=int(d)) for d in rng.integers(0, 184, N)],
    "amount": np.round(np.clip(amt, 5, 5_000_000), 2),
    "currency": rng.choice(["CAD", "USD"], N, p=[0.7, 0.3]),
    "counterparty": rng.choice(cptys, N),
    "reference": ["INV-" + str(r) for r in rng.choice(90_000_000, N, replace=False) + 10_000_000],
    "source_system": src,
})

even = [i for i in range(N) if int(round(base.amount[i] * 100)) % 2 == 0 and base.amount[i] >= 50]
equal_ids = set(int(i) for i in rng.choice(even, EQUAL_SPLITS, replace=False))

a_lines, b_rec = {}, {}
for i, r in enumerate(base.itertuples(index=False)):
    b = r._asdict()
    b["copy"] = 0
    b_rec[i] = b
    amt = b["amount"]
    if b["currency"] == "USD" and rng.random() < FX_P:
        amt = round(amt + rng.choice([-0.01, 0.01]), 2)

    if i in equal_ids:
        parts = [b["amount"] / 2] * 2
    elif rng.random() < SPLIT_P and amt >= 50:
        parts = split_amount(amt, int(rng.choice([2, 3])))
    else:
        parts = [amt]

    a_lines[i] = []
    for p in parts:
        l = dict(b)
        l["amount"] = round(p, 2)
        l["post_date"] = b["post_date"] + timedelta(days=lag())
        a_lines[i].append(l)

# exactly 1200 exceptions, each on a different payment
plan = (["duplicate"] * 300 + ["missing_in_b"] * 250 + ["missing_in_a"] * 250
        + ["amount_mismatch"] * 250 + ["wrong_cpty_ref"] * 150)
pool = [i for i in range(N) if i not in equal_ids]
picked = rng.choice(pool, len(plan), replace=False)

# the tiny mismatches go on single line payments
singles = [n for n, (i, k) in enumerate(zip(picked, plan)) if k == "amount_mismatch" and len(a_lines[i]) == 1]
tiny = set(singles[:TINY_MISMATCH])

extra_a, extra_b = [], []
used_refs = set(base["reference"])

for n, (i, kind) in enumerate(zip(picked, plan)):
    tag = (n + 1, kind)
    lines = a_lines[i]
    if kind == "missing_in_b":
        del b_rec[i]
        for l in lines:
            l["_exc"] = tag
    elif kind == "missing_in_a":
        del a_lines[i]
        b_rec[i]["_exc"] = tag
    elif kind == "amount_mismatch":
        l = lines[rng.integers(len(lines))]
        if n in tiny:
            l["amount"] = round(b_rec[i]["amount"] + float(rng.choice([-0.02, -0.01, 0.01, 0.02])), 2)
        else:
            delta = round(float(rng.uniform(1.01, 250)), 2)
            if l["amount"] - delta > 1 and rng.random() < 0.5:
                delta = -delta
            l["amount"] = round(l["amount"] + delta, 2)
        l["_exc"] = tag
        b_rec[i]["_exc"] = tag
    elif kind == "wrong_cpty_ref":
        l = lines[rng.integers(len(lines))]
        if n % 2 == 0:
            l["counterparty"] = rng.choice([c for c in cptys[:200] if c != l["counterparty"]])
        else:
            ref = l["reference"]
            while ref in used_refs:
                pos = int(rng.integers(4, len(ref)))
                ref = ref[:pos] + str(rng.integers(10)) + ref[pos + 1:]
            used_refs.add(ref)
            l["reference"] = ref
        l["_exc"] = tag
        b_rec[i]["_exc"] = tag
    else:
        # double posting. bank side mostly, erp re-keys land the same day
        if rng.random() < 0.75:
            d = dict(lines[rng.integers(len(lines))])
            off = 0 if rng.random() < SAME_DAY_DUP_P else int(rng.integers(1, 3))
            d["post_date"] = d["post_date"] + timedelta(days=off)
            d["copy"], d["_exc"] = 1, tag
            extra_a.append(d)
        else:
            d = dict(b_rec[i])
            d["copy"], d["_exc"] = 1, tag
            extra_b.append(d)

# separate stream so this doesnt move anything else
rng2 = np.random.default_rng(SEED + 1)
clean = [i for i in range(N) if i not in set(picked) and len(a_lines[i]) == 1 and base.currency[i] == "USD"]
for i in rng2.choice(clean, FX_TWICE, replace=False):
    a_lines[i][0]["amount"] = round(b_rec[i]["amount"] + float(rng2.choice([-0.03, 0.03])), 2)


def finish(rows, prefix):
    # copies get ids after the original when they post the same day
    df = pd.DataFrame(rows)
    df = df.sample(frac=1, random_state=SEED).sort_values(["post_date", "copy"], kind="stable").reset_index(drop=True)
    df.insert(0, "payment_id", [f"{prefix}{n:07d}" for n in range(1, len(df) + 1)])
    return df


A = finish([l for ls in a_lines.values() for l in ls] + extra_a, "BNK")
B = finish(list(b_rec.values()) + extra_b, "ERP")

truth = []
for led, df in (("A", A), ("B", B)):
    for pid, exc in zip(df["payment_id"], df["_exc"]):
        if isinstance(exc, tuple):
            truth.append({"exception_id": exc[0], "record_id": pid, "ledger": led, "type": exc[1]})
truth = pd.DataFrame(truth).sort_values(["exception_id", "ledger", "record_id"])

cols = ["payment_id", "post_date", "amount", "currency", "counterparty", "reference", "source_system"]
os.makedirs(OUT, exist_ok=True)
A[cols].to_csv(f"{OUT}/ledger_a.csv", index=False, float_format="%.2f")
B[cols].to_csv(f"{OUT}/ledger_b.csv", index=False, float_format="%.2f")
truth.to_csv(f"{OUT}/truth.csv", index=False)

print(f"ledger_a {len(A)} rows, ledger_b {len(B)} rows")
print(f"exceptions {truth.exception_id.nunique()} ({len(truth)} truth rows)")
print(truth.groupby("type").exception_id.nunique().to_string())
