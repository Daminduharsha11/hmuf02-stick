#!/usr/bin/env python3
"""Verify an EDL backup: compare every partition inside the full-disk dump
(edl rf) against the per-partition files (edl rl).

Usage:  python verify_backup.py [dump] [partition_folder]
        defaults: uz801-stock.bin  uz801_stock
Needs:  only Python 3. Reads the GPT itself, so no sfdisk/gdisk/root needed.
Safe:   read-only, no loop devices.
"""
import hashlib
import os
import struct
import sys

CHUNK = 4 * 1024 * 1024
# Partitions that hold your identity/calibration or get touched by the firmware swap
CRITICAL = {'modem', 'modemst1', 'modemst2', 'fsg', 'fsc', 'ssd', 'persist',
            'sec', 'ddr', 'sbl1', 'tz', 'hyp', 'aboot', 'rpm', 'boot'}


def read_gpt(path):
    """Return [{'name', 'start', 'size'}, ...] (bytes) from the GPT in the dump."""
    with open(path, 'rb') as f:
        for sector in (512, 4096):
            f.seek(sector)
            hdr = f.read(92)
            if hdr[:8] == b'EFI PART':
                break
        else:
            raise ValueError('no GPT header found (is this a full-disk dump from "edl rf"?)')
        entries_lba, count, esize = struct.unpack_from('<QII', hdr, 72)
        f.seek(entries_lba * sector)
        data = f.read(count * esize)
    parts = []
    for i in range(count):
        e = data[i * esize:(i + 1) * esize]
        if len(e) < 128 or e[:16] == b'\0' * 16:
            continue
        first, last = struct.unpack_from('<QQ', e, 32)
        name = e[56:128].decode('utf-16le', 'replace').split('\0', 1)[0]
        parts.append({'name': name or f'part{i + 1}',
                      'start': first * sector,
                      'size': (last - first + 1) * sector})
    return parts


def sha256_range(path, offset, length):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        f.seek(offset)
        left = length
        while left > 0:
            block = f.read(min(CHUNK, left))
            if not block:
                break
            h.update(block)
            left -= len(block)
    return h.hexdigest()


def find_part_file(folder, name):
    """Find the rl file for a partition (modem.bin, modem.img, or plain modem)."""
    for fn in sorted(os.listdir(folder)):
        if fn.lower().endswith('.xml'):
            continue
        stem = fn.rsplit('.', 1)[0] if '.' in fn else fn
        if stem.lower() == name.lower() or fn.lower() == name.lower():
            return os.path.join(folder, fn)
    return None


def human(n):
    for unit in ('B', 'KiB', 'MiB', 'GiB'):
        if n < 1024 or unit == 'GiB':
            return f'{n:.0f} {unit}' if unit == 'B' else f'{n:.1f} {unit}'
        n /= 1024


def main():
    dump = sys.argv[1] if len(sys.argv) > 1 else 'uz801-stock.bin'
    folder = sys.argv[2] if len(sys.argv) > 2 else 'uz801_stock'
    print('Working folder:', os.getcwd())
    if not os.path.isfile(dump):
        sys.exit(f'\nDump not found: {dump}\n'
                 'Run this from the folder that holds it, or pass the full path.\n'
                 f'To find it:  find ~ -name "{os.path.basename(dump)}" 2>/dev/null')
    if not os.path.isdir(folder):
        sys.exit(f'\nPartition folder not found: {folder}\n'
                 f'To find it:  find ~ -type d -name "{os.path.basename(folder)}" 2>/dev/null')

    try:
        parts = read_gpt(dump)
    except (ValueError, struct.error) as e:
        sys.exit(f'\nCould not read the partition table: {e}')
    print(f'Dump: {dump} ({human(os.path.getsize(dump))}), {len(parts)} partitions\n')

    ok = bad = 0
    print(f'{"partition":<12}{"size":>11}   result   (* = critical)')
    for p in parts:
        name, start, size = p['name'], p['start'], p['size']
        mark = '*' if name.lower() in CRITICAL else ' '
        f = find_part_file(folder, name)
        if not f:
            print(f'{name:<11}{mark}{human(size):>11}   NO FILE', flush=True)
            bad += 1
            continue
        fsize = os.path.getsize(f)
        if fsize != size:
            print(f'{name:<11}{mark}{human(size):>11}   SIZE MISMATCH '
                  f'(file is {fsize} bytes, partition is {size})', flush=True)
            bad += 1
            continue
        same = sha256_range(dump, start, size) == sha256_range(f, 0, fsize)
        print(f'{name:<11}{mark}{human(size):>11}   {"OK" if same else "DIFF"}', flush=True)
        ok, bad = (ok + 1, bad) if same else (ok, bad + 1)

    print(f'\n{ok} OK, {bad} problem(s).')
    if bad == 0:
        print('Both dumps agree on every partition.')
    else:
        print('Fix the DIFF / MISMATCH / NO FILE lines before flashing anything.')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
