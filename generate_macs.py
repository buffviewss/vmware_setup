#!/usr/bin/env python3
"""
Generate MAC addresses for given OUI(s) and save to files.

- Modes:
  1) Batch mode: if 'inputOUI.txt' exists in the same folder, read OUIs from it.
     For each valid OUI, generate 10 unique MACs and:
        - write a per-OUI file (can be disabled via WRITE_PER_OUI_FILES)
        - also append ALL results into a single combined file: macs_ALL_<timestamp>.txt
  2) Interactive fallback: prompt for a single OUI and generate 10 MACs (per-OUI file).

- Input OUI format: XX:XX:XX or XX-XX-XX (e.g., 00:1B:21 or 00-1B-21).
- Ensures each MAC is unicast & globally-administered (I/G=0, U/L=0 on first octet).
- No external libraries. Works on Windows 10/11/Server (and VMware VM).
"""

import os
import re
import random
from datetime import datetime
from typing import List, Tuple

INPUT_FILE = "inputOUI.txt"
TARGET_COUNT_PER_OUI = 10
WRITE_PER_OUI_FILES = True   # set False if you want ONLY the single combined file

OUI_PATTERN = re.compile(r"^[0-9A-Fa-f]{2}([-:])[0-9A-Fa-f]{2}\1[0-9A-Fa-f]{2}$")

def normalize_oui(oui: str) -> str:
    """Normalize OUI to 'XX:XX:XX' and validate I/G & U/L bits."""
    text = oui.strip()
    if not text or text.startswith("#"):
        raise ValueError("Empty or commented line.")
    if not OUI_PATTERN.match(text):
        raise ValueError("OUI must be in the form XX:XX:XX or XX-XX-XX (hex digits).")
    sep = ":" if ":" in text else "-"
    parts = [p.upper() for p in text.split(sep)]
    first_octet = int(parts[0], 16)
    # I/G bit (bit0) must be 0 = unicast; U/L bit (bit1) must be 0 = globally administered
    if (first_octet & 0b1) or (first_octet & 0b10):
        raise ValueError("First octet indicates multicast or locally-administered. Use a vendor OUI.")
    return ":".join(parts)

def rand_octet() -> str:
    return f"{random.randint(0, 255):02X}"

def gen_mac_from_oui(oui: str) -> str:
    """Generate a MAC address 'XX:XX:XX:AA:BB:CC' using the given OUI."""
    return f"{oui}:{rand_octet()}:{rand_octet()}:{rand_octet()}"

def write_mac_file(oui: str, macs: List[str], stamp: str) -> str:
    safe_oui = oui.replace(":", "")
    filename = f"macs_{safe_oui}_{stamp}.txt"
    filepath = os.path.abspath(filename)
    with open(filename, "w", encoding="utf-8") as f:
        for m in macs:
            f.write(m + "\n")
    return filepath

def append_to_combined(combined_path: str, oui: str, macs: List[str]) -> None:
    with open(combined_path, "a", encoding="utf-8") as f:
        f.write(f"[OUI: {oui}]  ({len(macs)} MACs)\n")
        for m in macs:
            f.write(m + "\n")
        f.write("\n")

def generate_for_oui(oui: str, count: int = TARGET_COUNT_PER_OUI) -> List[str]:
    seen = set()
    macs = []
    while len(macs) < count:
        mac = gen_mac_from_oui(oui)
        if mac not in seen:
            seen.add(mac)
            macs.append(mac)
    return macs

def load_ouis_from_file(path: str) -> List[str]:
    """Read OUIs from text file, normalize, de-duplicate while preserving order."""
    normalized = []
    seen = set()
    with open(path, "r", encoding="utf-8") as f:
        for idx, line in enumerate(f, start=1):
            raw = line.strip()
            if not raw or raw.startswith("#"):
                continue
            try:
                n = normalize_oui(raw)
            except ValueError as e:
                print(f"[WARN] Line {idx}: '{raw}' skipped ({e}).")
                continue
            if n not in seen:
                seen.add(n)
                normalized.append(n)
    return normalized

def interactive_single_oui():
    print("=== MAC Generator (10 addresses) ===")
    print("Example OUI: 00:1B:21  (Intel) | also supports format 00-1B-21")
    user_oui = input("Enter OUI (XX:XX:XX): ").strip()
    try:
        oui = normalize_oui(user_oui)
    except ValueError as e:
        print(f"[ERROR] {e}")
        return

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    macs = generate_for_oui(oui, TARGET_COUNT_PER_OUI)
    per_path = write_mac_file(oui, macs, stamp)

    print("\n# Generated MAC addresses:")
    for m in macs:
        print(m)
    print(f"\nSaved {TARGET_COUNT_PER_OUI} MACs to: {per_path}")

def batch_mode(path: str):
    print(f"=== Batch Mode: reading OUIs from '{path}' ===")
    ouis = load_ouis_from_file(path)
    if not ouis:
        print("[INFO] No valid OUIs found in file. Falling back to interactive mode.")
        interactive_single_oui()
        return

    # One timestamp for the whole batch so files align together
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    combined_filename = f"macs_ALL_{stamp}.txt"
    combined_path = os.path.abspath(combined_filename)

    # Write combined file header
    with open(combined_filename, "w", encoding="utf-8") as f:
        f.write("# Combined MAC list\n")
        f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"# Source file: {os.path.abspath(path)}\n")
        f.write(f"# Each OUI section below contains {TARGET_COUNT_PER_OUI} MACs\n\n")

    results = []
    for oui in ouis:
        print(f"\n[+] Generating {TARGET_COUNT_PER_OUI} MACs for OUI {oui} ...")
        macs = generate_for_oui(oui, TARGET_COUNT_PER_OUI)

        if WRITE_PER_OUI_FILES:
            per_path = write_mac_file(oui, macs, stamp)
            print(f"    Saved per-OUI file: {per_path}")
        else:
            per_path = None

        append_to_combined(combined_path, oui, macs)
        results.append((oui, per_path))

    # Summary
    print("\n=== Summary ===")
    for (oui, per_path) in results:
        if per_path:
            print(f"- {oui} -> {per_path}")
        else:
            print(f"- {oui} -> (per-OUI file disabled)")
    print(f"\nAll results combined into: {combined_path}")

def main():
    # If inputOUI.txt exists in current working directory, run batch mode
    if os.path.exists(INPUT_FILE):
        batch_mode(INPUT_FILE)
    else:
        interactive_single_oui()

if __name__ == "__main__":
    main()
