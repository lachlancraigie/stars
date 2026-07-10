"""Normalize off-vocabulary emotive tags in lines/*.json and regenerate all
elevenlabs/*.csv from the JSON (kills any CSV/JSON drift)."""
import csv, json, os, re, sys

LINES_DIR = r"d:\code\stars\resources\dialogue\lines"
CSV_DIR = r"d:\code\stars\resources\dialogue\elevenlabs"

VOCAB = {"EMPHASIS","CONFIDENT","REASSURING","TERRIFIED","NERVOUS","ANGRY","GRUFF","WARM","TIRED",
"EXHAUSTED","PANICKED","CALM","URGENT","SARCASTIC","DRY","GRIM","HOPEFUL","WHISPERS","SHOUTS",
"MUTTERS","LAUGHS","SIGHS","PAINED","FLIRTY","EMBARRASSED","SUSPICIOUS","CURIOUS","PROUD",
"DISMISSIVE","PLEADING","RESIGNED","DEADPAN"}
REMAP = {
    "DOUBT": "SUSPICIOUS", "WORRIED": "NERVOUS", "GRATEFUL": "WARM", "GENUINE": "WARM",
    "BANTER": "DRY", "HORRIFIED": "TERRIFIED", "GALLOWS": "GRIM", "FOCUS": "CALM",
    "STATUS": None, "ACKNOWLEDGMENT": None, "WHISTLES": None,  # None = drop tag
}
TAG_RE = re.compile(r"\[([A-Z ]+)\]\s?")

def fix_text(text, log, key):
    def repl(m):
        tag = m.group(1).strip()
        if tag in VOCAB:
            return m.group(0)
        if tag in REMAP:
            new = REMAP[tag]
            log.append(f"{key}: [{tag}] -> {'[' + new + ']' if new else 'dropped'}")
            return f"[{new}] " if new else ""
        log.append(f"{key}: UNKNOWN [{tag}] dropped")
        return ""
    return re.sub(r"  +", " ", TAG_RE.sub(repl, text)).strip()

changes = []
for name in sorted(os.listdir(LINES_DIR)):
    if not name.endswith(".json"):
        continue
    path = os.path.join(LINES_DIR, name)
    lines = json.load(open(path, encoding="utf-8"))
    dirty = False
    for ln in lines:
        fixed = fix_text(ln["text"], changes, ln.get("key", "?"))
        if fixed != ln["text"]:
            ln["text"] = fixed
            dirty = True
    if dirty:
        json.dump(lines, open(path, "w", encoding="utf-8", newline="\n"),
                  indent=2, ensure_ascii=False)
    # regenerate CSV from JSON regardless (canonical source of truth)
    tag_upper = os.path.splitext(name)[0].upper()
    csv_path = os.path.join(CSV_DIR, os.path.splitext(name)[0] + ".csv")
    with open(csv_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL)
        w.writerow(["id", "text"])
        for ln in lines:
            w.writerow([f"{tag_upper}_{ln['id']:05d}", ln["text"]])

print(f"{len(changes)} tag fixes:")
for c in changes:
    print(" ", c)
print("all CSVs regenerated from lines JSON")
