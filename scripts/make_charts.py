import os
import pandas as pd
# dashboard.png is a screenshot of the real power bi report, not made here
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

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


if __name__ == "__main__":
    flow()
    detection()
    print("charts saved to", IMG)
