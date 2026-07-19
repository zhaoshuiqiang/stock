#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UTF-8 + newline safe edit applier (ASCII-only source on purpose).

Why this exists: on this Windows host the editor's Write tool persists files
using the system code page (gb18030), which corrupts UTF-8 Chinese content, and
target Dart files use CRLF line endings. This applier always reads/writes target
files as UTF-8 and matches/writes using the target file's own newline style, so
edits to Chinese-containing CRLF files stay lossless.

Usage:
    python scripts/apply_edits.py <spec_file>

Spec format (spec may be CRLF or LF; if it contains non-ASCII, transcode
gb18030 -> utf-8 before running):

    @@FILE relative/or/absolute/path
    @@OLD
    <verbatim old text, may span multiple lines>
    @@NEW
    <verbatim new text, may span multiple lines>
    @@END

Rules:
  - Repeat the block (FILE/OLD/NEW/END) per edit.
  - OLD must match exactly once by default. Put "@@COUNT n" right after @@FILE
    to require n occurrences, or "@@COUNT all" to replace every occurrence.
  - Matching ignores line-ending style: OLD/NEW are normalized to LF, then
    converted to the target file's dominant newline before matching/writing.
Exit code is non-zero if any block fails (so mismatches are caught loudly).
"""

import io
import os
import sys


def _read(path):
    with io.open(path, encoding='utf-8', newline='') as f:
        return f.read()


def _write(path, text):
    with io.open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


def _dominant_newline(text):
    if text.count('\r\n') > 0:
        return '\r\n'
    if text.count('\r') > 0 and text.count('\n') == 0:
        return '\r'
    return '\n'


def _to_lf(text):
    return text.replace('\r\n', '\n').replace('\r', '\n')


def parse_blocks(spec_text):
    # splitlines() handles \r\n, \n and \r uniformly and drops terminators.
    lines = spec_text.splitlines()
    blocks = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.startswith('@@FILE '):
            path = line[len('@@FILE '):].strip()
            i += 1
            count = 1
            if i < n and lines[i].startswith('@@COUNT '):
                token = lines[i][len('@@COUNT '):].strip()
                count = 'all' if token == 'all' else int(token)
                i += 1
            assert i < n and lines[i].strip() == '@@OLD', (
                f'expected @@OLD near spec line {i + 1}')
            i += 1
            old_start = i
            while i < n and lines[i].strip() != '@@NEW':
                i += 1
            assert i < n, 'missing @@NEW'
            old_text = '\n'.join(lines[old_start:i])
            i += 1
            new_start = i
            while i < n and lines[i].strip() != '@@END':
                i += 1
            assert i < n, 'missing @@END'
            new_text = '\n'.join(lines[new_start:i])
            i += 1
            blocks.append((path, count, old_text, new_text))
        else:
            i += 1
    return blocks


def apply_block(path, count, old_lf, new_lf):
    if not os.path.exists(path):
        return False, f'file not found: {path}'
    content = _read(path)
    nl = _dominant_newline(content)
    old_text = old_lf.replace('\n', nl)
    new_text = new_lf.replace('\n', nl)
    occurrences = content.count(old_text)
    if count == 'all':
        if occurrences == 0:
            return False, f'OLD not found (0 occurrences): {path}'
        _write(path, content.replace(old_text, new_text))
        return True, f'replaced all {occurrences} in {path} (nl={nl!r})'
    if occurrences != count:
        return False, (f'OLD found {occurrences}x but expected {count}x in '
                       f'{path} (nl={nl!r}); refine the anchor')
    _write(path, content.replace(old_text, new_text, count))
    return True, f'replaced {count} in {path} (nl={nl!r})'


def main():
    if len(sys.argv) != 2:
        print('usage: python scripts/apply_edits.py <spec_file>')
        sys.exit(2)
    spec_text = _read(sys.argv[1])
    try:
        blocks = parse_blocks(spec_text)
    except AssertionError as e:
        print(f'spec parse error: {e}')
        sys.exit(2)
    if not blocks:
        print('no edit blocks parsed; check spec format')
        sys.exit(2)
    failures = 0
    for idx, (path, count, old_text, new_text) in enumerate(blocks, 1):
        ok, msg = apply_block(path, count, old_text, new_text)
        print(f'[{"OK " if ok else "ERR"}] block {idx}: {msg}')
        if not ok:
            failures += 1
    if failures:
        print(f'FAILED: {failures}/{len(blocks)} blocks did not apply')
        sys.exit(1)
    print(f'SUCCESS: applied {len(blocks)} blocks')


if __name__ == '__main__':
    main()
