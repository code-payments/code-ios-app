#!/usr/bin/env python3
"""
Generate binary lookup tables from the Rust curve tables.

This script reads the table.rs file from the flipcash-program repo
and generates binary resource files for use by DiscreteBondingCurve.swift.

Usage:
    ./generate_curve_tables.py <path-to-table.rs>

Example:
    ./generate_curve_tables.py ../flipcash-program/api/src/table.rs

Binary format: Array of 128-bit little-endian unsigned integers
Each entry is 16 bytes (low 8 bytes + high 8 bytes)
"""

import argparse
import re
import struct
import sys
from pathlib import Path


def extract_table(content: str, table_name: str) -> list[int]:
    """Extract a table from the Rust source."""
    # Find the table definition
    pattern = rf'pub static {table_name}: &\[u128\] = &\[([\s\S]*?)\];'
    match = re.search(pattern, content)
    if not match:
        raise ValueError(f"Could not find table: {table_name}")

    table_content = match.group(1)

    # Extract all numbers (ignoring comments)
    numbers = []
    for line in table_content.split('\n'):
        # Remove comments
        line = re.sub(r'//.*$', '', line)
        # Find numbers
        for num_match in re.finditer(r'(\d+)', line):
            numbers.append(int(num_match.group(1)))

    return numbers


def write_binary_table(path: Path, values: list[int]):
    """Write table as binary file with 128-bit little-endian integers."""
    with open(path, 'wb') as f:
        for v in values:
            # Split into low and high 64-bit parts
            low = v & 0xFFFFFFFFFFFFFFFF
            high = v >> 64
            # Write as little-endian: low bytes first, then high bytes
            f.write(struct.pack('<QQ', low, high))


def main():
    parser = argparse.ArgumentParser(
        description="Generate binary lookup tables from Rust curve tables."
    )
    parser.add_argument(
        "rust_table_path",
        type=Path,
        help="Path to the Rust table.rs file (e.g., ../flipcash-program/api/src/table.rs)"
    )
    parser.add_argument(
        "-o", "--output-dir",
        type=Path,
        default=None,
        help="Output directory for binary files (default: FlipcashCore/Sources/FlipcashCore/Resources)"
    )
    args = parser.parse_args()

    rust_table_path = args.rust_table_path

    if not rust_table_path.exists():
        print(f"Error: Could not find {rust_table_path}")
        sys.exit(1)

    print(f"Reading {rust_table_path}...")
    content = rust_table_path.read_text()

    print("Extracting pricing table...")
    pricing = extract_table(content, "DISCRETE_PRICING_TABLE")
    print(f"  Found {len(pricing)} entries")

    print("Extracting cumulative value table...")
    cumulative = extract_table(content, "DISCRETE_CUMULATIVE_VALUE_TABLE")
    print(f"  Found {len(cumulative)} entries")

    # Determine output directory (relative to this script's location)
    if args.output_dir:
        resources_dir = args.output_dir
    else:
        script_dir = Path(__file__).parent.resolve()
        resources_dir = script_dir.parent / "FlipcashCore" / "Sources" / "FlipcashCore" / "Resources"

    resources_dir.mkdir(parents=True, exist_ok=True)

    # Write binary files
    pricing_path = resources_dir / "discrete_pricing_table.bin"
    print(f"Writing {pricing_path}...")
    write_binary_table(pricing_path, pricing)
    pricing_size = pricing_path.stat().st_size
    print(f"  Size: {pricing_size:,} bytes ({pricing_size / 1024 / 1024:.2f} MB)")

    cumulative_path = resources_dir / "discrete_cumulative_table.bin"
    print(f"Writing {cumulative_path}...")
    write_binary_table(cumulative_path, cumulative)
    cumulative_size = cumulative_path.stat().st_size
    print(f"  Size: {cumulative_size:,} bytes ({cumulative_size / 1024 / 1024:.2f} MB)")

    print("\nDone!")
    print(f"  Pricing table: {len(pricing)} entries")
    print(f"  Cumulative table: {len(cumulative)} entries")
    print(f"  Total binary size: {(pricing_size + cumulative_size) / 1024 / 1024:.2f} MB")


if __name__ == "__main__":
    main()
