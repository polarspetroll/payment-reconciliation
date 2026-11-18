import os
import pandas as pd
import psycopg
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

DSN = os.getenv("RECON_DSN", "postgresql://postgres:postgres@localhost:5432/recon")
IMG = "docs/images"
os.makedirs(IMG, exist_ok=True)
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.spines.top": False, "axes.spines.right": False})
BLUE, GREY, ORANGE = "#2a6fdb", "#9aa5b1", "#e8833a"


def flow():
    fig, ax = plt.subplots(figsize=(10, 3.2))
    ax.set_xlim(0, 10); ax.set_ylim(0, 3.2); ax.axis("off")
    boxes = {
        "Ledger A\n(bank)": (0.2, 2.0), "Ledger B\n(ERP)": (0.2, 0.4),
        "PostgreSQL\nv1 / v2 rules": (2.9, 1.2), "Exceptions\n+ evaluate.py": (5.4, 1.2),
        "Power BI\ndashboard": (7.9, 2.0), "z/OS batch\nDFSORT + COBOL": (7.9, 0.4),
    }
    for label, (x, y) in boxes.items():
        ax.add_patch(FancyBboxPatch((x, y), 1.9, 0.85, boxstyle="round,pad=0.05", fc="#eef3fc", ec=BLUE, lw=1.4))
        ax.text(x + 0.95, y + 0.42, label, ha="center", va="center", fontsize=10)
    arrows = [((2.1, 2.4), (2.9, 1.8)), ((2.1, 0.8), (2.9, 1.4)), ((4.8, 1.6), (5.4, 1.6)),
              ((7.3, 1.8), (7.9, 2.4)), ((7.3, 1.4), (7.9, 0.8))]
    for a, b in arrows:
        ax.annotate("", xy=b, xytext=a, arrowprops=dict(arrowstyle="->", color="#333", lw=1.3))
    ax.text(5, 3.05, "Payment reconciliation flow", ha="center", fontsize=12, weight="bold")
    fig.savefig(f"{IMG}/flow.png", dpi=150, bbox_inches="tight")
    plt.close(fig)


def detection():
    v1 = pd.read_csv("results/v1_by_type.csv").set_index("type")
    v2 = pd.read_csv("results/v2_by_type.csv").set_index("type")
    s1 = pd.read_csv("results/v1_summary.csv").iloc[0]
    s2 = pd.read_csv("results/v2_summary.csv").iloc[0]
    types = list(v1.index)
    fig, (ax, ax2) = plt.subplots(1, 2, figsize=(10, 3.6), gridspec_kw={"width_ratios": [3, 1.3]})
    x = range(len(types))
    ax.bar([i - 0.2 for i in x], v1.detection_pct, 0.4, label="v1", color=GREY)
    ax.bar([i + 0.2 for i in x], v2.loc[types].detection_pct, 0.4, label="v2", color=BLUE)
    ax.set_xticks(list(x), [t.replace("_", " ") for t in types])
    ax.set_ylim(0, 110); ax.set_ylabel("detection rate %"); ax.legend(frameon=False, loc="lower left")
    ax.set_title("Detection by exception type")
    for i, t in enumerate(types):
        ax.text(i - 0.2, v1.detection_pct[t] + 1.5, f"{v1.detection_pct[t]:.0f}", ha="center", fontsize=8)
        ax.text(i + 0.2, v2.detection_pct[t] + 1.5, f"{v2.detection_pct[t]:.0f}", ha="center", fontsize=8)

    ax2.bar(["v1", "v2"], [s1.fp_rate_pct, s2.fp_rate_pct], color=[GREY, BLUE], width=0.55)
    ax2.set_ylim(0, 110); ax2.set_title("False positive rate %")
    for i, v in enumerate([s1.fp_rate_pct, s2.fp_rate_pct]):
        ax2.text(i, v + 2, f"{v:.2f}%", ha="center", fontsize=9)
    fig.tight_layout()
    fig.savefig(f"{IMG}/v1_vs_v2.png", dpi=150, bbox_inches="tight")
    plt.close(fig)


def dashboard():
    # preview of the same measures, the real one is built in power bi desktop
    with psycopg.connect(DSN) as conn:
        cur = conn.execute("select * from v_recon")
        df = pd.DataFrame(cur.fetchall(), columns=[c.name for c in cur.description])
    df["amount_cad"] = df.amount_cad.astype(float)
    ex = df[df.status == "EXCEPTION"]

    fig = plt.figure(figsize=(12, 6.5))
    gs = fig.add_gridspec(3, 3, height_ratios=[0.55, 1.4, 1.4], hspace=0.6, wspace=0.35)
    cards = [("Exception count", f"{len(ex):,}"), ("Exception rate", f"{len(ex) / len(df):.2%}"),
             ("At risk (C\\$)", f"{ex.amount_cad.sum() / 1e6:,.1f}M")]
    for i, (k, v) in enumerate(cards):
        a = fig.add_subplot(gs[0, i]); a.axis("off")
        a.add_patch(FancyBboxPatch((0, 0), 1, 1, boxstyle="round,pad=0.02", fc="#eef3fc", ec=BLUE, transform=a.transAxes))
        a.text(0.5, 0.62, v, ha="center", va="center", fontsize=18, weight="bold", color=BLUE, transform=a.transAxes)
        a.text(0.5, 0.22, k, ha="center", va="center", fontsize=10, transform=a.transAxes)

    a = fig.add_subplot(gs[1, 0])
    t = ex.exception_type.value_counts().sort_values()
    a.barh([s.replace("_", " ") for s in t.index], t.values, color=BLUE); a.set_title("By type", fontsize=10)

    a = fig.add_subplot(gs[1, 1])
    s = ex.source_system.value_counts().sort_values()
    a.barh(s.index, s.values, color=ORANGE); a.set_title("By source system", fontsize=10)

    a = fig.add_subplot(gs[1, 2])
    w = ex.groupby("week_start").size()
    a.plot(pd.to_datetime(w.index), w.values, color=BLUE, marker="o", ms=3)
    a.set_title("By week", fontsize=10); a.tick_params(axis="x", labelsize=7, rotation=30)

    a = fig.add_subplot(gs[2, :]); a.axis("off")
    top = ex.sort_values("amount_cad", ascending=False).head(6)
    cells = [[r.payment_id, r.ledger, r.exception_type, r.counterparty[:22], r.reference, f"{r.amount_cad:,.2f}"] for r in top.itertuples()]
    tb = a.table(cellText=cells, colLabels=["payment id", "ledger", "type", "counterparty", "reference", "amount C$"],
                 loc="upper center", cellLoc="left")
    tb.auto_set_font_size(False); tb.set_fontsize(8.5); tb.scale(1, 1.3)
    a.set_title("Open exceptions, largest first", fontsize=10)
    fig.suptitle("Reconciliation exceptions (v2 rules)", fontsize=13, weight="bold")
    fig.savefig(f"{IMG}/dashboard.png", dpi=130, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    flow()
    detection()
    dashboard()
    print("charts saved to", IMG)
