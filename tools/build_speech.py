"""Render the ship's spoken vocabulary to assets/generated/voice/.

Run:
    python tools/build_speech.py            # SAPI voices, the default
    python tools/build_speech.py --engine wavdir --raw <dir>

Why this exists
---------------
ATC has to say things the game only knows at runtime: your berth number, the
speed you are over by, the marker you just missed. A bank of whole sentences
cannot do that, and a runtime text-to-speech call cannot be made to sound like a
radio, because it does not pass through the audio buses.

So the lines are cut where the numbers go. Every comms line in the project is a
FORMAT STRING - "REDUCE SPEED - %.0f M/S" - and this script reads those strings
straight out of the source, renders each literal piece between the specifiers as
its own clip, and writes a manifest saying how to put them back together with
the slot values spoken in between. At runtime Speech.gd matches the finished
line against those patterns and plays piece, number, piece.

The consequence worth stating: THE LINES ARE NOT COPIED ANYWHERE. Change a comms
line in GameState or DockingSystem, re-run this, and the spoken form changes with
it. A hand-written script beside the code would have disagreed with it inside a
week, which is exactly the drift CLAUDE.md is written to prevent.

data/speech/lines.json holds only what the source cannot tell you: which voice
speaks for which source, how to say the things a synthesiser gets wrong, and the
handful of lines the pilot transmits.

Licensing
---------
The default engine is the Windows SAPI voices, whose OUTPUT is licence-grey to
redistribute. Everything downstream of tools/tts_sapi.ps1 works on plain WAV, so
swapping in a permissively-licensed engine is one flag and a rebuild. See
CREDITS.md.
"""

import argparse
import glob
import hashlib
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGUE = os.path.join(ROOT, "data", "speech", "lines.json")
OUT_DIR = os.path.join(ROOT, "assets", "generated", "voice")
MANIFEST = os.path.join(OUT_DIR, "manifest.json")

## Files whose comms lines the ship should be able to say.
SOURCE_GLOBS = ["autoload/GameState.gd", "systems/*.gd", "systems/hardware/*.gd"]

## A GDScript string literal, and a printf specifier. `%%` is a literal percent
## and must not be mistaken for a slot.
LITERAL = r'"((?:[^"\\]|\\.)*)"'
SPECIFIER = re.compile(r"%%|%[-+ #0-9.*]*[sdfxXeEgGoc]")

## Joins voice and text before hashing. A unit separator rather than a NUL:
## it cannot occur in a comms line, and unlike NUL it survives being written
## into a source file and read back by a GDScript String, so the smoke test
## can recompute the same id and prove a clip is named after its own content.
SEPARATOR = "\u001f"


# --- Reading the corpus ---------------------------------------------------------

def scan_corpus():
    """Every comms line in the project, as (source, format string) pairs.

    Four shapes of call site, because the project writes comms four ways: the
    general post_comms, DockingSystem's standing _atc and momentary _call, and
    the wave-off / violation reasons, which are composed INTO another line and so
    have to be sayable on their own.
    """
    patterns = [
        ("post", re.compile(r"post_comms\(\s*" + LITERAL + r"\s*,\s*" + LITERAL)),
        ("atc", re.compile(r"\b_atc\(\s*" + LITERAL + r"(?:\s*,\s*" + LITERAL + r")?")),
        ("call", re.compile(r"\b_call\(\s*" + LITERAL + r"(?:\s*,\s*" + LITERAL + r")?")),
        ("reason", re.compile(r"\b(?:_wave_off|_violation|_reprimand|_bounce)\(\s*" + LITERAL)),
    ]
    files = []
    for pattern in SOURCE_GLOBS:
        files.extend(sorted(glob.glob(os.path.join(ROOT, pattern))))

    seen = set()
    out = []
    for path in files:
        text = io.open(path, encoding="utf-8").read()
        for kind, rx in patterns:
            for match in rx.finditer(text):
                groups = match.groups()
                if kind == "post":
                    pairs = [(groups[0], groups[1])]
                elif kind == "reason":
                    # A reason is quoted into an ATC line, so the harbour says it.
                    pairs = [("ATC", groups[0])]
                else:
                    pairs = [("ATC", g) for g in groups if g]
                for source, line in pairs:
                    key = (source, line)
                    if line and key not in seen:
                        seen.add(key)
                        out.append(key)
    return out


def split_line(line):
    """Split a format string into alternating literal pieces and slots.

    Returns a list where a str is a literal to render and an int is the index of
    the slot that goes there. `%%` collapses back to a literal percent sign.
    """
    parts = []
    slot = 0
    cursor = 0
    for match in SPECIFIER.finditer(line):
        piece = line[cursor:match.start()]
        if match.group(0) == "%%":
            parts.append(piece + "%")
            cursor = match.end()
            continue
        if piece:
            parts.append(piece)
        parts.append(slot)
        slot += 1
        cursor = match.end()
    tail = line[cursor:]
    if tail:
        parts.append(tail)

    # Merge adjacent literals produced by a `%%` collapse.
    merged = []
    for part in parts:
        if merged and isinstance(part, str) and isinstance(merged[-1], str):
            merged[-1] += part
        else:
            merged.append(part)
    return merged


def sayable(text):
    """A piece worth rendering: it has letters or digits in it.

    Splitting on specifiers leaves fragments like ") " and " / " behind. Reading
    those aloud is worse than leaving the gap.
    """
    return bool(re.search(r"[A-Za-z0-9]", text))


# --- Pronunciation --------------------------------------------------------------

def make_pronouncer(catalogue):
    """Text as written -> text as spoken.

    A synthesiser reads "M/S" as a fraction and "7741-C" as a subtraction. These
    are the places the written form and the spoken form genuinely differ; the
    rules live in the catalogue because they are judgements, not facts about the
    code.
    """
    rules = [(re.compile(a), b) for a, b in catalogue["pronounce"]["rules"]]

    def speak(text):
        out = text
        for rx, replacement in rules:
            out = rx.sub(replacement, out)
        # Collapse the punctuation that survives, so the engine does not pause on
        # a dangling comma left behind by a stripped specifier.
        out = re.sub(r"\s+", " ", out).strip(" ,-")
        return out

    return speak


def phonetic_words(text, phonetic):
    """Spell a mixed letters-and-digits token the way a lane reads a tail number."""
    words = []
    for char in text.upper():
        if char.isdigit():
            words.append(DIGIT_NAMES[int(char)])
        elif char in phonetic:
            words.append(phonetic[char])
    return words


DIGIT_NAMES = ["ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN",
               "EIGHT", "NINER"]


def read_ship():
    """The hull's identity, quoted from its ShipDefinition rather than written here.

    A second hull answers to its own callsign for free, which is the same rule
    TailPlate.gd follows for the builder's plate.
    """
    ships = sorted(glob.glob(os.path.join(ROOT, "data", "ships", "*.tres")))
    out = []
    for path in ships:
        text = io.open(path, encoding="utf-8").read()
        fields = {}
        for key in ("display_name", "registry"):
            match = re.search(key + r'\s*=\s*"([^"]*)"', text)
            if match:
                fields[key] = match.group(1)
        if fields.get("display_name"):
            out.append(fields)
    return out


def read_factions():
    names = []
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "factions", "*.tres"))):
        match = re.search(r'display_name\s*=\s*"([^"]*)"',
                          io.open(path, encoding="utf-8").read())
        if match:
            names.append(match.group(1))
    return names


# --- Audio ----------------------------------------------------------------------

def read_wav(path):
    with wave.open(path, "rb") as f:
        frames = f.readframes(f.getnframes())
        rate = f.getframerate()
        channels = f.getnchannels()
    data = np.frombuffer(frames, dtype=np.int16).astype(np.float64) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return data, rate


def write_wav(path, data, rate):
    pcm = (np.clip(data, -1.0, 1.0) * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(pcm.tobytes())


def bandpass(sig, low, high, rate):
    """FFT-domain band limit. The band IS the radio."""
    spec = np.fft.rfft(sig)
    freq = np.fft.rfftfreq(len(sig), 1.0 / rate)
    gain = 1.0 / np.sqrt(1.0 + (freq / max(high, 1.0)) ** 8)
    gain *= 1.0 / np.sqrt(1.0 + (max(low, 1.0) / np.maximum(freq, 1e-9)) ** 8)
    return np.fft.irfft(spec * gain, len(sig))


def trim(sig, rate, floor=0.006, margin=0.02):
    """Cut the synthesiser's leading and trailing padding.

    Segments get played back to back, so padding is not silence between words —
    it is a stutter in the middle of a sentence.
    """
    loud = np.abs(sig) > floor
    if not loud.any():
        return sig[:0]
    first, last = np.argmax(loud), len(loud) - np.argmax(loud[::-1])
    pad = int(margin * rate)
    return sig[max(0, first - pad):min(len(sig), last + pad)]


def compress(sig, threshold=0.25, ratio=4.0):
    """Even out the level so a quiet word is as present as a loud one."""
    magnitude = np.abs(sig)
    over = magnitude > threshold
    out = sig.copy()
    out[over] = np.sign(sig[over]) * (threshold + (magnitude[over] - threshold) / ratio)
    return out


def treat(sig, rate, voice):
    """Put a rendered clip through its voice's channel. Returns (signal, rate)."""
    sig = trim(sig, rate)
    if len(sig) == 0:
        return sig, rate
    low, high = voice["band"]
    sig = bandpass(sig, low, high, rate)
    sig = compress(sig)
    if voice.get("noise", 0.0) > 0.0:
        # A carrier is never silent. The bed is what makes it a channel someone
        # is transmitting on rather than a recording.
        bed = np.random.default_rng(7).standard_normal(len(sig))
        sig = sig + bandpass(bed, low, high, rate) * voice["noise"]
    peak = np.max(np.abs(sig))
    if peak > 1e-9:
        sig = sig * (0.82 / peak)
    return resample(sig, rate, voice.get("rate_hz", rate))


def resample(sig, rate, new_rate):
    """Band-limited resample by cropping the spectrum.

    Exact, and free here because everything upstream already works in the FFT
    domain. Dropping a voice to its own band's rate is not a compromise: a
    channel that stops at 3.4 kHz has nothing above 8 kHz to keep, and carrying
    silence up to 22 kHz costs real bytes in the repository.
    """
    if new_rate == rate or len(sig) == 0:
        return sig, rate
    count = max(1, int(round(len(sig) * float(new_rate) / rate)))
    return np.fft.irfft(np.fft.rfft(sig), count) * (float(count) / len(sig)), new_rate


## CRC-32 table for the Ogg page checksum: polynomial 0x04c11db7, not reflected,
## no initial or final XOR. Not the same CRC-32 as zlib's, which is why it is
## spelled out here rather than imported.
_OGG_CRC_TABLE = []
for _i in range(256):
    _r = _i << 24
    for _ in range(8):
        _r = ((_r << 1) ^ 0x04c11db7) & 0xFFFFFFFF if _r & 0x80000000 \
            else (_r << 1) & 0xFFFFFFFF
    _OGG_CRC_TABLE.append(_r)


def _ogg_crc(buf):
    crc = 0
    for byte in buf:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _OGG_CRC_TABLE[((crc >> 24) & 0xFF) ^ byte]
    return crc


def canonicalise_ogg(path, serial):
    """Give an encoded file a deterministic bitstream serial number.

    Why: libvorbis picks the Ogg serial at random on every encode, so two runs
    over identical audio produce files differing in 28 bytes — the serial in each
    page header, and the page CRC that covers it. Twenty-eight bytes is enough
    for git to call all three hundred clips modified, which would mean a 1.8 MB
    phantom diff every time anyone re-ran this script. That is precisely the
    thing that stops people re-running it.

    ffmpeg's `-serial_offset` is documented but is not honoured by the build
    here, so the field is rewritten directly. The serial lives at offset 14 of
    each page header and the CRC at 22, computed over the whole page with the CRC
    field zeroed. Deriving the serial from the clip's own id keeps every file
    unique, which is what a real encoder would have produced anyway.

    tools/build_sfx.py gets the same property for free from a seeded RNG. This is
    the voice bank paying the same debt.
    """
    data = bytearray(io.open(path, "rb").read())
    cursor = 0
    while cursor < len(data):
        if data[cursor:cursor + 4] != b"OggS":
            raise ValueError("%s: not an Ogg page at byte %d" % (path, cursor))
        segments = data[cursor + 26]
        size = 27 + segments + sum(data[cursor + 27:cursor + 27 + segments])
        struct.pack_into("<I", data, cursor + 14, serial)
        struct.pack_into("<I", data, cursor + 22, 0)
        struct.pack_into("<I", data, cursor + 22,
                         _ogg_crc(bytes(data[cursor:cursor + size])))
        cursor += size
    io.open(path, "wb").write(bytes(data))


def encode(wav_path, ogg_path, quality="0"):
    # -q:a, not -b:a. libvorbis treats a low bitrate target as a suggestion and
    # overshot it by three times on clips this short; the quality scale actually
    # binds.
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
         "-ac", "1", "-c:a", "libvorbis", "-q:a", quality, ogg_path],
        check=True)


# --- Build ----------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", default="sapi", choices=["sapi", "wavdir"],
                        help="sapi renders with the Windows voices; wavdir reuses "
                             "already-rendered WAVs from --raw (any engine, or a "
                             "human).")
    parser.add_argument("--raw", default=None,
                        help="Directory of raw per-clip WAVs. Kept between runs so "
                             "the treatment can be re-tuned without re-rendering.")
    parser.add_argument("--quality", default="0",
                        help="libvorbis -q:a. 0 is about 32 kbps mono and is "
                             "transparent for band-limited speech.")
    args = parser.parse_args()

    catalogue = json.load(io.open(CATALOGUE, encoding="utf-8"))
    voices = {k: v for k, v in catalogue["voices"].items() if not k.startswith("_")}
    sources = {k: v for k, v in catalogue["sources"].items() if not k.startswith("_")}
    phonetic = {k: v for k, v in catalogue["phonetic"].items() if not k.startswith("_")}
    speak_as = make_pronouncer(catalogue)

    raw_dir = args.raw or os.path.join(ROOT, "build", "speech", "raw")
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)

    # clip key (voice, spoken text) -> id. One clip per distinct thing said in a
    # given voice; a phrase shared by two sources in the same voice is rendered
    # once.
    clips = {}

    def clip_id(voice_name, text):
        """The id for one thing said in one voice.

        CONTENT-ADDRESSED, and that is not a detail. An earlier version numbered
        clips sequentially in discovery order, so adding or removing a single
        entry renumbered everything after it — while the raw renders cached on
        disk under the old numbers stayed put. The bank then played the right
        FILE for the wrong ENTRY: digits in the pilot's voice, a four-second
        callsign served by a one-second clip. Nothing failed; it just spoke
        nonsense.

        Deriving the id from what is actually said makes that impossible. It also
        keeps the .ogg filenames stable across catalogue edits, so a changed line
        is a one-file diff instead of a renumbering of three hundred.
        """
        spoken = speak_as(text)
        if not spoken or not sayable(spoken):
            return None
        key = (voice_name, spoken)
        if key not in clips:
            digest = hashlib.sha1(SEPARATOR.join([voice_name, spoken]).encode("utf-8"))
            clips[key] = "c" + digest.hexdigest()[:12]
        return clips[key]

    # --- Lines, straight out of the source ----------------------------------
    # Lines the catalogue says are never spoken are dropped here rather than at
    # runtime, so nothing is rendered for them at all.
    never = [re.compile(pattern)
             for pattern in catalogue.get("never_speak", {}).get("patterns", [])]

    lines = []
    skipped = 0
    for source, raw_line in scan_corpus():
        voice_name = sources.get(source, "silent")
        if voice_name == "silent" or voice_name not in voices:
            continue
        if any(rx.search(raw_line) for rx in never):
            skipped += 1
            continue
        parts = split_line(raw_line)
        if not any(isinstance(p, str) and sayable(p) for p in parts):
            continue  # a line that is nothing but a slot matches everything
        pattern = ""
        emitted = []
        for part in parts:
            if isinstance(part, int):
                pattern += "(.*?)"
                emitted.append({"slot": part})
            else:
                pattern += re.escape(part)
                cid = clip_id(voice_name, part)
                if cid:
                    emitted.append({"clip": cid})
        lines.append({
            "source": source,
            "voice": voice_name,
            "pattern": "^" + pattern + "$",
            "parts": emitted,
            # How much of the line is fixed text. Speech.gd tries the most
            # specific patterns first, so a line that is mostly slots can never
            # swallow one that is mostly words.
            "weight": sum(len(p) for p in parts if isinstance(p, str)),
        })
    lines.sort(key=lambda entry: -entry["weight"])

    # --- The vocabulary that fills the slots ---------------------------------
    line_voices = sorted({entry["voice"] for entry in lines})
    spoken_voices = sorted(set(line_voices) | {"pilot"})
    words = {v: {} for v in spoken_voices}
    digits = {v: [] for v in spoken_voices}
    phon = {v: {} for v in spoken_voices}

    vocabulary = list(catalogue["slot_words"]["words"])
    vocabulary += read_factions()
    vocabulary += ["%s CONTROL" % name for name in read_factions()]

    # The pilot transmits five fixed lines whose only slots are the station and
    # our own callsign, so it needs the station names and nothing else. Giving it
    # the full vocabulary rendered eighty clips of markers and digits that no
    # pilot line can ever reach.
    for voice_name in spoken_voices:
        if voice_name not in line_voices:
            for word in sorted(set(read_factions() + ["%s CONTROL" % n for n in read_factions()])):
                cid = clip_id(voice_name, word)
                if cid:
                    words[voice_name][word] = cid
            continue
        for word in sorted(set(vocabulary)):
            cid = clip_id(voice_name, word)
            if cid:
                words[voice_name][word] = cid
        for value, name in enumerate(DIGIT_NAMES):
            digits[voice_name].append(clip_id(voice_name, name))
        for extra in ("POINT", "MINUS", "HUNDRED", "THOUSAND"):
            words[voice_name][extra] = clip_id(voice_name, extra)
        for letter, name in phonetic.items():
            phon[voice_name][letter] = clip_id(voice_name, name)

    # --- The tail number ------------------------------------------------------
    # Full identity on first contact, the last three of the registry thereafter.
    callsigns = {}
    for ship in read_ship():
        name = ship["display_name"]
        registry = ship.get("registry", "")
        # "SV KESTREL" -> "SIERRA VICTOR KESTREL": an initialism is spelled, a
        # word is said.
        spoken_name = []
        for token in name.split():
            if len(token) <= 3 and token.isupper() and token.isalpha():
                spoken_name.extend(phonetic_words(token, phonetic))
            else:
                spoken_name.append(token)
        letters = re.sub(r"[^A-Za-z0-9]", "", registry)
        full = " ".join(spoken_name + phonetic_words(registry, phonetic))
        short = " ".join(phonetic_words(letters[-3:], phonetic)) if letters else ""
        entry = {}
        for voice_name in spoken_voices:
            entry[voice_name] = {
                "full": clip_id(voice_name, full),
                "short": clip_id(voice_name, short) if short else None,
            }
        callsigns[name] = entry

    # --- What the pilot transmits --------------------------------------------
    pilot = {}
    for key, template in catalogue["pilot_lines"].items():
        if key.startswith("_"):
            continue
        emitted = []
        for chunk in re.split(r"(\{[a-z_]+\})", template):
            if not chunk:
                continue
            if chunk.startswith("{"):
                emitted.append({"named": chunk[1:-1]})
            else:
                cid = clip_id("pilot", chunk)
                if cid:
                    emitted.append({"clip": cid})
        pilot[key] = emitted

    # --- Render ---------------------------------------------------------------
    jobs = []
    for (voice_name, text), cid in sorted(clips.items(), key=lambda kv: kv[1]):
        # raw_dir is a cache across runs. It is safe to reuse ONLY because cid is
        # a hash of (voice, text): a cached file can never belong to a different
        # line than the one asking for it.
        raw_path = os.path.join(raw_dir, cid + ".wav")
        if args.engine == "sapi" and not os.path.exists(raw_path):
            jobs.append({
                "voice": voices[voice_name]["engine_voice"],
                "rate": voices[voice_name].get("rate", 0),
                "text": text,
                "out": raw_path,
            })

    print("%d clips (%d lines, %d voices, %d lines never spoken). %d need rendering."
          % (len(clips), len(lines), len(spoken_voices), skipped, len(jobs)))

    if jobs:
        if args.engine != "sapi":
            missing = [j["out"] for j in jobs][:5]
            sys.exit("--engine %s but these raw clips are absent: %s"
                     % (args.engine, ", ".join(missing)))
        job_file = os.path.join(raw_dir, "jobs.json")
        json.dump(jobs, io.open(job_file, "w", encoding="utf-8"))
        shim = os.path.join(ROOT, "tools", "tts_sapi.ps1")
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        if not powershell:
            sys.exit("No PowerShell found; cannot drive the SAPI voices.")
        subprocess.run([powershell, "-NoProfile", "-File", shim,
                        "-JobFile", job_file], check=True)

    # --- Treat and encode -----------------------------------------------------
    print("Treating and encoding...")
    encoded = 0
    total_bytes = 0
    with tempfile.TemporaryDirectory() as scratch:
        for (voice_name, _text), cid in sorted(clips.items(), key=lambda kv: kv[1]):
            raw_path = os.path.join(raw_dir, cid + ".wav")
            if not os.path.exists(raw_path):
                print("  missing raw clip for %s (%s)" % (cid, voice_name))
                continue
            data, rate = read_wav(raw_path)
            data, out_rate = treat(data, rate, voices[voice_name])
            if len(data) == 0:
                continue
            staged = os.path.join(scratch, cid + ".wav")
            write_wav(staged, data, out_rate)
            ogg = os.path.join(OUT_DIR, cid + ".ogg")
            encode(staged, ogg, args.quality)
            # The id is already a hash of the clip's content, so this makes the
            # serial a function of the content too: same words, same bytes.
            canonicalise_ogg(ogg, int(cid[1:9], 16))
            total_bytes += os.path.getsize(ogg)
            encoded += 1

    manifest = {
        "clips": {cid: {"voice": v, "text": t} for (v, t), cid in clips.items()},
        "lines": lines,
        "words": words,
        "digits": digits,
        "phonetic": phon,
        "callsigns": callsigns,
        "pilot": pilot,
        "voices": {k: {"bus": v["bus"], "squelch": v.get("squelch", False)}
                   for k, v in voices.items()},
        "sources": sources,
        "hush_while_cutting": catalogue.get("hush_while_cutting", {}).get("voices", []),
    }
    json.dump(manifest, io.open(MANIFEST, "w", encoding="utf-8"), indent=1)

    print("Done. %d clips encoded, %.1f KB total, manifest at %s"
          % (encoded, total_bytes / 1024.0, os.path.relpath(MANIFEST, ROOT)))


if __name__ == "__main__":
    main()
