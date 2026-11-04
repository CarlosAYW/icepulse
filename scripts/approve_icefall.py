"""Append an approved icefall issue to add_new/new_icefalls.csv.

Reads the issue form text from the environment variable ISSUE_BODY. The text comes
from the public, so it is only ever treated as data and reduced to one CSV field.
"""

import os
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

CSV_PATH = Path("add_new/new_icefalls.csv")
COLUMNS = {
    "Name": "name",
    "Latitude": "latitude",
    "Longitude": "longitude",
    "Difficulty": "difficulty",
    "Height (m)": "icefall_height_m",
    "Approach": "approach",
    "Descent": "descent",
    "Description": "description",
    "First ascent": "first_ascent",
    "Topo link": "topo_url",
}


def parse_form(body):
    sections = re.split(r"^### +", body.replace("\r\n", "\n"), flags=re.MULTILINE)
    fields = {}
    for section in sections:
        label, _, value = section.partition("\n")
        column = COLUMNS.get(label.strip())
        if column:
            value = value.strip()
            fields[column] = "" if value == "_No response_" else value
    return fields


def clean(value):
    value = re.sub(r"\s+", " ", value).strip()
    return value.replace(";", ",").replace('"', "'")


def coordinate(value, limit):
    number = float(value.strip().replace(",", "."))
    if not abs(number) <= limit:
        raise ValueError(f"{value} is out of range")
    return f"{number:.6f}"


def build_row(fields):
    row = {column: clean(fields.get(column, "")) for column in COLUMNS.values()}
    if not row["name"]:
        raise ValueError("name is missing")
    row["latitude"] = coordinate(row["latitude"], 90)
    row["longitude"] = coordinate(row["longitude"], 180)
    if row["topo_url"] and urlparse(row["topo_url"]).scheme not in ("http", "https"):
        raise ValueError("topo link must start with http or https")
    return row


def append_row(path, row):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    header = lines[0].split(";")
    line = ";".join("" if column == "uid" else row.get(column, "") for column in header)
    if line in lines:
        return False
    with path.open("a", encoding="utf-8", newline="\n") as f:
        if text and not text.endswith("\n"):
            f.write("\n")
        f.write(line + "\n")
    return True


def main():
    try:
        row = build_row(parse_form(os.environ["ISSUE_BODY"]))
    except (KeyError, ValueError) as error:
        print(f"Could not read the submission: {error}")
        return 1
    added = append_row(CSV_PATH, row)
    print(("Added: " if added else "Already listed: ") + row["name"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
