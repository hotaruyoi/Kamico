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
parser.add_argument('--jdk', default=os.environ.get('JAVA_HOME'), required=not os.environ.get('JAVA_HOME'))
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
for architecture in [*machines, 'universal']:
    path = folder / f'Kamico-{version}-android-{architecture}.apk'
    badging = run(tools / 'aapt2.exe', 'dump', 'badging', path)
    assert f"name='app.jmpic.jm_mobile' versionCode='{build}' versionName='{version}'" in badging
    assert "application-label:'kamico'" in badging
    assert 'application-debuggable' not in badging
    assert "sdkVersion:'24'" in badging
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

bundle = folder / f'Kamico-{version}-android.aab'
check_native(bundle, 'base/lib', set(machines))
verification = run(Path(args.jdk) / 'bin/jarsigner.exe', '-J-Duser.language=en',
                   '-J-Duser.country=US', '-verify', bundle)
assert 'jar verified.' in verification
certificate = run(Path(args.jdk) / 'bin/keytool.exe', '-J-Duser.language=en',
                  '-J-Duser.country=US', '-printcert', '-jarfile', bundle)
signer = re.search(r'SHA256:\s*([\dA-F:]+)', certificate).group(1).replace(':', '').lower()
assert signer == expected_signer
records.append({'file': bundle.name, 'bytes': bundle.stat().st_size,
                'abis': sorted(machines), 'certificateSha256': signer,
                'sha256': hashlib.sha256(bundle.read_bytes()).hexdigest()})
(folder / 'artifacts.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
for item in records:
    print(item['file'], item['bytes'], ','.join(item['abis']), 'verified')
