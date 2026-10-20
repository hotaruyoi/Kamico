"""Verify delivered source files against the current workspace, without building."""
from pathlib import Path
import hashlib
import json
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
version = sys.argv[1]
with zipfile.ZipFile(root / 'releases' / version / 'source.zip') as archive:
    names = {name.removeprefix('./'): name for name in archive.namelist()}
    files = {}
    for directory in ['lib', 'test', 'tool']:
        for path in (root / directory).rglob('*'):
            if not path.is_file():
                continue
            relative = path.relative_to(root).as_posix()
            if relative.startswith('tool/baseline15/') or '__pycache__' in path.parts:
                continue
            current = path.read_bytes()
            saved = archive.read(names[relative])
            if current != saved:
                raise SystemExit(f'Archive differs: {relative}')
            files[relative] = hashlib.sha256(current).hexdigest()
    for relative in ['pubspec.yaml', 'pubspec.lock', 'android/local.properties',
                     'android/app/src/main/kotlin/app/jmpic/jm_mobile/PdfDownloads.kt']:
        current = (root / relative).read_bytes()
        if current != archive.read(names[relative]):
            raise SystemExit(f'Archive differs: {relative}')
        files[relative] = hashlib.sha256(current).hexdigest()
record = {'version': version, 'matched_files': len(files), 'sha256': files}
(root / 'docs' / f'source-check-{version}.json').write_text(
    json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'Source archive matches {len(files)} workspace files.')
