"""Verify architecture, identity, signature and payload of Android release files."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--sdk', default=os.environ.get('ANDROID_HOME'), required=not os.environ.get('ANDROID_HOME'))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
version, build = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)',
                           (root / 'pubspec.yaml').read_text(encoding='utf-8-sig'), re.M).groups()
folder = root / 'releases' / version / 'distribution'
tools = max((Path(args.sdk) / 'build-tools').iterdir(),
            key=lambda p: tuple(int(x) for x in re.findall(r'\d+', p.name)))
expected_signer = 'c9c2e03d943cfa9a1f4ea7f2386075789db7ebb9ae360b035d337594cdcf78b2'
machines = {'arm64-v8a': (2, 183), 'armeabi-v7a': (1, 40), 'x86_64': (2, 62)}


def run(*command):
    return subprocess.check_output([str(x) for x in command], encoding='utf-8', errors='replace')


def check_native(path, prefix, abis):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, f'Corrupt ZIP: {path}'
        actual = {name.split('/')[len(prefix.split('/'))] for name in archive.namelist()
                  if name.startswith(prefix + '/') and name.endswith('/libapp.so')}
        assert actual == abis, (path.name, actual, abis)
        for abi in abis:
            for library in ['libapp.so', 'libflutter.so']:
                payload = archive.read(f'{prefix}/{abi}/{library}')
                assert payload[:4] == b'\x7fELF'
                assert payload[5] == 1
                assert (payload[4], struct.unpack_from('<H', payload, 18)[0]) == machines[abi]
                assert b'ext.kamico.profile' not in payload


records = []
for architecture in ['arm64-v8a', 'x86_64', 'universal']:
    path = folder / f'Kamico-{version}-android-{architecture}.apk'
    badging = run(tools / 'aapt2.exe', 'dump', 'badging', path)
    assert f"name='app.jmpic.jm_mobile' versionCode='{build}' versionName='{version}'" in badging
    assert "application-label:'kamico'" in badging
    assert 'application-debuggable' not in badging
    assert re.search(r"^(?:minSdkVersion|sdkVersion):'24'$", badging, re.M)
    assert "targetSdkVersion:'36'" in badging
    expected = set(machines) if architecture == 'universal' else {architecture}
    check_native(path, 'lib', expected)
    signing = run(tools / 'apksigner.bat', 'verify', '--print-certs', path)
    signer = re.search(r'Signer #1 certificate SHA-256 digest: (\w+)', signing).group(1)
    assert signer == expected_signer
    records.append({'file': path.name, 'version': f'{version}+{build}',
                    'bytes': path.stat().st_size, 'abis': sorted(expected),
                    'certificateSha256': signer,
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})

(folder.parent / 'apk-verification.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
for item in records:
    print(item['file'], item['bytes'], ','.join(item['abis']), 'verified')
