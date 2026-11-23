"""Build assets/qiraat/variants.json from a Quran Tajweed Engine checkout.

The farsh (word-level differences of the ten readers) comes unchanged from the
engine's data/qiraat-variants.json. This tool only:

* maps each juncture's Hafs token span onto the word numbers of the bundled
  Madani line layout (by matching letter skeletons token by token), and
* keeps the Arabic text and the attribution (readers / transmitters).

The English renderings, transliterations and notes are left out: the engine's
CREDITS ask to clear them with the Quran Foundation before a release.

Usage:
    python3 tool/import_qiraat_variants.py <engine checkout> [--check]
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "assets/qiraat/variants.json"
SOURCE = "https://github.com/TheAbubakrAbu/Quran-Tajweed-Engine"
LETTERS = re.compile(r"[^ء-غف-ي]")

# Arabic display names. Ids and grouping come from the engine's tables.
READER_NAMES = {
    6: "أبو جعفر",
    1: "ابن عامر",
    7: "نافع",
    2: "حمزة",
    8: "ابن كثير",
    3: "خلف العاشر",
    9: "أبو عمرو",
    4: "الكسائي",
    10: "يعقوب",
    5: "عاصم",
}
TRANSMITTER_NAMES = {
    1: "حفص",
    2: "شعبة",
    3: "قالون",
    4: "ورش",
    5: "البزي",
    6: "قنبل",
    7: "الدوري عن أبي عمرو",
    8: "السوسي",
    9: "هشام",
    10: "ابن ذكوان",
    11: "خلف عن حمزة",
    12: "خلاد",
    13: "الدوري عن الكسائي",
    14: "أبو الحارث",
    15: "ابن وردان",
    16: "ابن جماز",
    17: "رويس",
    18: "روح",
    19: "إسحاق",
    20: "إدريس",
}


def skeleton(token):
    token = token.replace("ٱ", "ا").replace("ى", "ي").replace("ی", "ي")
    token = "".join(
        char
        for char in unicodedata.normalize("NFKD", token)
        if unicodedata.category(char) != "Mn"
    )
    return LETTERS.sub("", token)


def layout_words():
    layout = json.loads(
        (ROOT / "assets/mushaf/layout/hafs_madani_604.json").read_text(encoding="utf-8")
    )
    words = {}
    for page in layout["pages"]:
        for line in page["lines"]:
            for word in line.get("words") or []:
                surah, ayah, index = word["location"].split(":")
                words.setdefault(f"{surah}:{ayah}", {})[int(index)] = word["text"]
    return words


def token_map(source_text, ours):
    """Source token index (0-based) -> layout word number (1-based), or None."""
    source = [(i, skeleton(t)) for i, t in enumerate(source_text.split()) if skeleton(t)]
    target = [(i, skeleton(ours[i])) for i in sorted(ours) if skeleton(ours[i])]
    if [s for _, s in source] != [s for _, s in target]:
        return None
    return {s: t for (s, _), (t, _) in zip(source, target)}


HAFS_TRANSMITTER = 1
HAFS_READER = 5
LONG_VOWELS_AND_HAMZA = re.compile("[اىيوءأإآؤئةه]")


def word_cores(text):
    return {
        core
        for token in re.split(r"[\s…\-.]+", text)
        if len(core := LONG_VOWELS_AND_HAMZA.sub("", skeleton(token))) >= 2
    }


def placement_consistent(entry):
    """The source's own Hafs reading must share a word with the headword the
    span points at; otherwise the span is not trusted and the juncture is kept
    at ayah level (the engine's own rule for spans it cannot place)."""
    hafs = [r for r in entry["readings"] if HAFS_TRANSMITTER in r["transmitters"]] or [
        r for r in entry["readings"] if HAFS_READER in r["readers"]
    ]
    if not hafs or not entry["word"]:
        return True
    reading, head = word_cores(hafs[0]["text"]), word_cores(entry["word"])
    if not reading or not head:
        return True
    return any(a in b or b in a for a in reading for b in head)


def build(engine):
    data = engine / "data"
    raw = json.loads((data / "qiraat-variants.json").read_text(encoding="utf-8"))
    quran = json.loads((data / "quran.json").read_text(encoding="utf-8"))
    source_text = {
        f"{surah['id']}:{ayah['id']}": ayah["textArabic"]
        for surah in quran
        for ayah in surah["ayahs"]
    }
    ours = layout_words()
    maps = {}
    junctures = []
    placed = unplaced = 0
    inconsistent = []
    for ayah_key in sorted(raw["ayahs"], key=lambda k: tuple(map(int, k.split(":")))):
        for entry in raw["ayahs"][ayah_key]:
            segments = []
            trusted = placement_consistent(entry)
            if not trusted:
                inconsistent.append(f"{ayah_key} {entry['word']}")
            for segment in entry["segments"]:
                span = segment.get("span")
                words = None
                if span and trusted:
                    key = segment["ayah"]
                    if key not in maps:
                        maps[key] = token_map(source_text[key], ours.get(key, {}))
                    mapping = maps[key]
                    if mapping and span[0] in mapping and span[1] in mapping:
                        words = [mapping[span[0]], mapping[span[1]]]
                placed += words is not None
                unplaced += words is None
                segments.append({"ayah": segment["ayah"], "words": words})
            junctures.append(
                {
                    "word": entry["word"],
                    "segments": segments,
                    "readings": [
                        {
                            "text": reading["text"],
                            "readers": reading["readers"],
                            "transmitters": reading["transmitters"],
                        }
                        for reading in entry["readings"]
                    ],
                }
            )
    readers = {
        key: {"name": READER_NAMES[int(key)], "position": value["position"]}
        for key, value in raw["readers"].items()
    }
    transmitters = {
        key: {
            "name": TRANSMITTER_NAMES[int(key)],
            "reader": value["reader"],
            "riwayah": value["riwayah"],
        }
        for key, value in raw["transmitters"].items()
    }
    revision = subprocess.run(
        ["git", "-C", str(engine), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    output = {
        "schemaVersion": "1.0.0",
        "source": SOURCE,
        "revision": revision,
        "sourceFile": "data/qiraat-variants.json",
        "origin": "Quran.com (Quran Foundation) qiraat matrix, via Quran Tajweed Engine",
        "readers": readers,
        "transmitters": transmitters,
        "junctures": junctures,
    }
    return output, placed, unplaced, inconsistent


def process_engine(engine_path: Path, check: bool):
    output, placed, unplaced, inconsistent = build(engine_path)
    text = json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n"
    print(
        f"{len(output['junctures'])} junctures, {placed} segments placed on layout "
        f"words, {unplaced} kept at ayah level"
    )
    print(f"{len(inconsistent)} junctures whose span disagrees with their Hafs reading:")
    for item in inconsistent:
        print(f"  {item}")
    if check:
        if not OUTPUT.exists():
            sys.exit(f"{OUTPUT} does not exist")
        if OUTPUT.read_text(encoding="utf-8") != text:
            sys.exit(f"{OUTPUT} is out of date")
        print("OK: assets/qiraat/variants.json matches engine source.")
        return
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text, encoding="utf-8")
    license_file = OUTPUT.parent / "LICENSE-QuranTajweedEngine.txt"
    license_file.write_text((engine_path / "LICENSE").read_text(encoding="utf-8"), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path, nargs="?", help="Quran Tajweed Engine checkout")
    parser.add_argument("--check", action="store_true", help="fail if the asset differs")
    args = parser.parse_args()

    if args.engine:
        process_engine(args.engine, args.check)
        return

    if not OUTPUT.exists():
        sys.exit(f"No engine checkout provided and {OUTPUT} does not exist to read pinned revision")

    with open(OUTPUT, "r", encoding="utf-8") as f:
        current_data = json.load(f)
    revision = current_data.get("revision")
    source_url = current_data.get("source", SOURCE)

    with tempfile.TemporaryDirectory() as td:
        engine_dir = Path(td)
        try:
            subprocess.run(["git", "clone", "--depth", "1", source_url, str(engine_dir)], check=True)
            head_rev = subprocess.run(
                ["git", "-C", str(engine_dir), "rev-parse", "HEAD"],
                capture_output=True,
                text=True,
            ).stdout.strip()
            if revision and head_rev != revision:
                subprocess.run(["git", "-C", str(engine_dir), "fetch", "--depth", "1", "origin", revision], check=True)
                subprocess.run(["git", "-C", str(engine_dir), "checkout", revision], check=True)
        except subprocess.CalledProcessError:
            subprocess.run(["git", "clone", source_url, str(engine_dir)], check=True)
            if revision:
                subprocess.run(["git", "-C", str(engine_dir), "checkout", revision], check=True)
        process_engine(engine_dir, args.check)


if __name__ == "__main__":
    main()
