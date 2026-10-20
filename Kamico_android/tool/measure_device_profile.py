"""Collect FrameTiming from the explicit synthetic profile entrypoint only."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import urlencode
from urllib.request import urlopen
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--adb', required=True)
parser.add_argument('--serial', required=True)
parser.add_argument('--run-log', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--reader-menu-followup', action='store_true')
args = parser.parse_args()


def adb(*command):
    return subprocess.check_output(
        [args.adb, '-s', args.serial, *command],
        encoding='utf-8', errors='replace', env=os.environ,
    )


log = Path(args.run_log).read_text(encoding='utf-8-sig', errors='replace')
match = re.search(r'A Dart VM Service.*?(http://127\.0\.0\.1:\d+/[^\s]+/)', log)
if not match:
    raise RuntimeError('No local VM service found in the profile run log')
base = match.group(1)


def rpc(method, **params):
    with urlopen(base + method + '?' + urlencode(params), timeout=15) as reply:
        data = json.load(reply)
    if 'error' in data:
        raise RuntimeError(str(data['error']))
    return data['result']


isolate = next(
    entry['id'] for entry in rpc('getVM')['isolates']
    if 'ext.kamico.profile' in rpc('getIsolate', isolateId=entry['id'])
        .get('extensionRPCs', [])
)


def profile(op, **params):
    return rpc('ext.kamico.profile', isolateId=isolate, op=op, **params)


def scene(name):
    profile('scene', name='home' if name != 'home' else 'downloads')
    time.sleep(.2)
    profile('scene', name=name)
    time.sleep(1.5)


def tree():
    adb('shell', 'uiautomator', 'dump', '/data/local/tmp/kamico-profile.xml')
    return ET.fromstring(adb('shell', 'cat', '/data/local/tmp/kamico-profile.xml'))


def label(node):
    return node.get('text') or node.get('content-desc', '')


def text_center(label):
    node = next(node for node in tree().iter('node') if
                (node.get('text') or node.get('content-desc', '')) == label)
    left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
    return str((left + right) // 2), str((top + bottom) // 2)


width, height = map(int, re.findall(r'(\d+)x(\d+)', adb('shell', 'wm', 'size'))[-1])


def swipe(index):
    a, b = (int(height * .77), int(height * .31))
    if index % 2:
        a, b = b, a
    adb('shell', 'input', 'swipe', str(width // 2), str(a), str(width // 2), str(b), '800')
    time.sleep(.08)


def stats(values):
    ordered = sorted(values)
    return {
        'p50': round(ordered[max(0, math.ceil(len(ordered) * .5) - 1)], 3),
        'p95': round(ordered[max(0, math.ceil(len(ordered) * .95) - 1)], 3),
        'max': round(max(ordered), 3),
    }


results = []


def sample(name, action, repeats):
    time.sleep(.4)
    profile('start')
    for index in range(repeats):
        action(index)
    time.sleep(.4)
    data = profile('stop')
    frames = data['frames']
    if data['mode'] != 'profile' or not frames:
        raise RuntimeError('Expected nonempty device profile frames')
    budget = 1000 / data['refreshHz']
    result = {
        'scenario': name, 'mode': data['mode'], 'refreshHz': data['refreshHz'],
        'frameBudgetMs': round(budget, 3), 'frameCount': len(frames),
        'buildMs': stats([frame['buildMs'] for frame in frames]),
        'rasterMs': stats([frame['rasterMs'] for frame in frames]),
        'totalMs': stats([frame['totalMs'] for frame in frames]),
        'overBudgetFrames': sum(max(frame['buildMs'], frame['rasterMs']) > budget for frame in frames),
        'frames': frames,
    }
    results.append(result)
    print(json.dumps({key: value for key, value in result.items() if key != 'frames'}, ensure_ascii=False), flush=True)


if args.reader_menu_followup:
    saved = json.loads(Path(args.output).read_text(encoding='utf-8'))
    scene('reader')
    for i in range(2):
        swipe(i)

    def warmed_menu(_):
        adb('shell', 'input', 'tap', str(width // 2), str(height // 2))
        time.sleep(.35)

    for i in range(6):
        warmed_menu(i)
    sample('reader: 24 overlay toggles after 6 warmup toggles', warmed_menu, 24)
    saved['scenarios'].extend(results)
    Path(args.output).write_text(json.dumps(saved, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    raise SystemExit(0)

scene('home')
assert any(label(node) == 'Kamico · JM' for node in tree().iter('node'))
for i in range(2):
    swipe(i)
sample('discovery: 96 synthetic covers, 8 alternating 800ms swipes after warmup', swipe, 8)
scene('downloads')
for i in range(2):
    swipe(i)
sample('offline library: 96 synthetic books, 8 alternating 800ms swipes after warmup', swipe, 8)
scene('downloads')
select_label = next(label(node) for node in tree().iter('node')
                    if label(node) in {'选择', 'Select'})
position = text_center(select_label)
adb('shell', 'input', 'tap', *position)
selected_tree = tree()
assert any(label(node) == select_label for node in selected_tree.iter('node'))
assert any(label(node) in {'已选 0', '0 selected'} for node in selected_tree.iter('node'))
adb('shell', 'input', 'tap', *position)
assert not any(label(node).startswith('已选 ') or re.fullmatch(r'\d+ selected', label(node))
               for node in tree().iter('node'))


def toggle_selection(_):
    adb('shell', 'input', 'tap', *position)
    time.sleep(.28)


sample('offline library: 12 selection toggles', toggle_selection, 12)
scene('reader')
for i in range(2):
    swipe(i)
sample('vertical reader: 20 synthetic 720x1100 pages, 8 alternating swipes', swipe, 8)


def toggle_reader(_):
    adb('shell', 'input', 'tap', str(width // 2), str(height // 2))
    time.sleep(.28)


sample('reader: 12 overlay menu toggles', toggle_reader, 12)
memory = adb('shell', 'dumpsys', 'meminfo', 'app.jmpic.jm_mobile.debug')
memory_match = re.search(r'TOTAL PSS:\s*(\d+)', memory)
package_info = adb('shell', 'dumpsys', 'package', 'app.jmpic.jm_mobile.debug')
installed_version = re.search(r'versionName=(\S+)', package_info).group(1)
installed_build = re.search(r'versionCode=(\d+)', package_info).group(1)
output = {
    'version': installed_version + '+' + installed_build, 'synthetic': True, 'mode': 'profile',
    'deviceModel': adb('shell', 'getprop', 'ro.product.model').strip(),
    'androidApi': adb('shell', 'getprop', 'ro.build.version.sdk').strip(),
    'lowPower': adb('shell', 'settings', 'get', 'global', 'low_power').strip(),
    'memoryPssKiBAtEnd': int(memory_match.group(1)) if memory_match else None,
    'selectionSemanticsPassed': True,
    'scenarios': results,
    'limits': 'Synthetic local covers and pages; no upstream or account writes. Profile frame timings are not sustained display FPS, real-network performance, or a before/after speedup comparison.',
}
Path(args.output).write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
