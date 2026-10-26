#!/usr/bin/env python3
"""Verify that generated packed MIFs reproduce their canonical ROM bytes."""

from pathlib import Path

from pack_core_roms import ROMS, ROM_BYTES, SLOT_BYTES, parse_byte_mif, parse_packed_mif


def packed_region(path: Path, region: int, words: int, size: int) -> bytes:
    raw = path.read_text(encoding="ascii").splitlines()
    values: dict[int, int] = {}
    in_content = False
    for source in raw:
        line = source.strip()
        if line == "CONTENT BEGIN":
            in_content = True
            continue
        if not in_content or not line or line == "END;" or ":" not in line:
            continue
        address, value = line.rstrip(";").split(":", 1)
        values[int(address, 16)] = int(value, 16)
    result = bytearray()
    for address in range(region * words, (region + 1) * words):
        value = values.get(address, 0)
        result.extend((value >> (lane * 8)) & 0xFF for lane in range(4))
    return bytes(result[:size])


def main() -> None:
    canonical = parse_byte_mif(ROMS / "rom.mif", ROM_BYTES)
    packed = parse_packed_mif(ROMS / "rom_packed.mif", ROM_BYTES)
    assert canonical == packed, "packed built-in ROM differs from rom.mif"

    cartridges = ROMS / "cartridge_roms_packed.mif"
    empty = bytes(SLOT_BYTES)
    diagnostic = parse_packed_mif(ROMS / "scsi_diag.mif", SLOT_BYTES)
    expected = (empty, diagnostic, empty, empty)
    for slot, content in enumerate(expected):
        actual = packed_region(cartridges, slot, 4096, SLOT_BYTES)
        assert actual == content, f"packed cartridge slot {slot} differs"
    print("PASS packed built-in and cartridge ROM images")


if __name__ == "__main__":
    main()
