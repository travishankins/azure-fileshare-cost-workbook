import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PANELS = {
    "Cost Per Share Summary - Current Month": "cost-per-share-summary",
    "Cost Per Share by Meter": "cost-per-share-detail",
    "Month-over-Month Cost Per Share": "month-over-month",
    "Daily Cost Trend Per Share": "daily-cost-trend",
}


def normalize_formats(value):
    if isinstance(value, dict):
        if value.get("style") == "currency":
            value["style"] = "decimal"
            value.pop("currency", None)
        for child in value.values():
            normalize_formats(child)
    elif isinstance(value, list):
        for child in value:
            normalize_formats(child)


def build(workbook):
    common = (ROOT / "queries/common.kql").read_text(encoding="utf-8")
    matched = set()
    for item in workbook["items"]:
        content = item.get("content", {})
        title = content.get("title")
        if title in PANELS:
            query = (ROOT / "queries" / (PANELS[title] + ".kql")).read_text(encoding="utf-8")
            content["query"] = common + "\n" + query
            normalize_formats(content)
            if content.get("visualization") == "tiles":
                content["tileSettings"]["rightContent"] = {"columnMatch": "Currency", "formatter": 1}
            matched.add(title)
        for parameter in content.get("parameters", []):
            if parameter["name"] == "Subscription":
                parameter.pop("defaultValue", None)
    if matched != set(PANELS):
        raise ValueError(f"Missing workbook panels: {set(PANELS) - matched}")
    return workbook


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = ROOT / "workbook/azure-fileshare-cost-workbook.json"
    original = json.loads(path.read_text(encoding="utf-8"))
    updated = build(json.loads(json.dumps(original)))
    if args.check:
        if original != updated:
            raise SystemExit("Workbook differs from query sources; run python scripts/build-workbook.py")
        print("Workbook query sources are synchronized")
    else:
        path.write_text(json.dumps(updated, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
