"""Assert native-device reader geometry through menu/system-bar transitions."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import urlencode
from urllib.request import urlopen

parser = argparse.ArgumentParser()
parser.add_argument('--adb', required=True)
parser.add_argument('--serial', required=True)
parser.add_argument('--run-log', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
text = Path(args.run_log).read_text(encoding='utf-8-sig', errors='replace')
base = re.search(r'A Dart VM Service.*?(http://127\.0\.0\.1:\d+/[^\s]+/)', text).group(1)


def rpc(method, **params):
    with urlopen(base + method + '?' + urlencode(params), timeout=15) as reply:
        result = json.load(reply)
    if 'error' in result:
        raise RuntimeError(str(result['error']))
    return result['result']


isolate = next(entry['id'] for entry in rpc('getVM')['isolates']
               if 'ext.kamico.profile' in rpc('getIsolate', isolateId=entry['id'])
               .get('extensionRPCs', []))


def probe(op, **params):
    return rpc('ext.kamico.profile', isolateId=isolate, op=op, **params)


def adb(*command):
    return subprocess.check_output([args.adb, '-s', args.serial, *command],
                                   encoding='utf-8', errors='replace')


probe('scene', name='home')
time.sleep(.2)
probe('scene', name='reader')
time.sleep(2)
width, height = map(int, re.findall(r'(\d+)x(\d+)', adb('shell', 'wm', 'size'))[-1])
adb('shell', 'input', 'swipe', str(width // 2), str(int(height * .77)),
    str(width // 2), str(int(height * .48)), '800')
time.sleep(1.5)
metadata = probe('snapshot')
before = metadata['layout']
steps = []
for toggle in range(4):
    adb('shell', 'input', 'tap', str(width // 2), str(height // 2))
    for tick in range(10):
        time.sleep(.05)
        steps.append({'toggle': toggle, 'tick': tick,
                      'layout': probe('snapshot')['layout']})

max_image_delta = 0.0
surface_changed = False
missing_anchor = False
anchors = {item['element']: item for item in before['images']
           if item['y'] < before['surface']['height'] and item['y'] + item['height'] > 0}
for step in steps:
    layout = step['layout']
    surface_changed |= layout['surface'] != before['surface']
    current = {item['element']: item for item in layout['images']}
    for identity, anchor in anchors.items():
        if identity not in current:
            missing_anchor = True
        else:
            max_image_delta = max(max_image_delta,
                                  abs(current[identity]['y'] - anchor['y']))
stable = not surface_changed and not missing_anchor and max_image_delta <= .5
report = {'stable': stable, 'mode': metadata['mode'], 'maxImageDeltaLogicalPx': max_image_delta,
          'surfaceChanged': surface_changed, 'missingAnchor': missing_anchor,
          'before': before, 'steps': steps}
Path(args.output).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps({key: report[key] for key in
                 ['stable', 'maxImageDeltaLogicalPx', 'surfaceChanged', 'missingAnchor']}))
raise SystemExit(0 if stable else 1)
