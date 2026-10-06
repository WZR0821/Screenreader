#!/usr/bin/env python3
"""Package a verified unsigned iPhoneOS app. Requires a completed Release build."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path, help='Release-iphoneos/ScreenTranslate.app')
parser.add_argument('output', type=Path, help='Output .ipa file')
args = parser.parse_args()
app = args.app.resolve()
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['DTPlatformName'] == 'iphoneos', 'A device build is required'
assert info['CFBundleShortVersionString'] == '1.0.0'
assert info['CFBundleVersion'] == '17'
assert info['CFBundleDisplayName'] == '读屏'
assert info['CFBundleName'] == 'Screenreader'
localized_names = {}
for locale, expected in [('en', 'Screenreader'), ('zh-Hans', '读屏')]:
    strings = app / (locale + '.lproj') / 'InfoPlist.strings'
    localized = json.loads(subprocess.check_output(['/usr/bin/plutil', '-convert', 'json', '-o', '-', str(strings)], text=True))
    assert localized['CFBundleDisplayName'] == expected
    localized_names[locale] = expected
assert (app / '读屏全文.shortcut').exists()
assert (app / '屏译全文.shortcut').exists(), 'Keep the signed legacy workflow for existing users'
assert info['UIDeviceFamily'] == [1], 'This deliverable targets iPhone only'
executable = app / info['CFBundleExecutable']
env = dict(os.environ)
architecture = subprocess.check_output(['xcrun', 'lipo', '-archs', str(executable)], env=env, text=True).strip()
assert architecture == 'arm64', architecture
unsigned_objects = [executable]
for p in app.rglob('*'):
    assert p.name not in {'_CodeSignature', 'embedded.mobileprovision'}, p
    assert not p.name.endswith('.xctest') and not p.name.startswith('XCTest'), p
    if p.is_file() and p != executable and p.read_bytes()[:4] in [b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe']:
        unsigned_objects.append(p)
for binary in unsigned_objects:
    result = subprocess.run(['/usr/bin/codesign', '-dv', str(binary)], capture_output=True, text=True)
    assert result.returncode != 0 and 'not signed at all' in result.stderr, result.stderr
binary = executable.read_bytes()
for marker in [b'fixture.invalid', b'ui-test-key', b'--ui-test', b'--fixture-image', b'--fixture-long', b'--fixture-askmode', b'--fixture-reader', b'--fixture-layout', b'--fixture-uncertain', b'--fixture-history', b'--fixture-japanese', b'DebugFixtures', b'SimulateActionButtonIntent', b'SimulatorActionButtonView', b'SimulatorScreenshot', b'demo-key', b'DATE_REVIEW']:
    assert marker not in binary, marker
metadata = json.loads((app / 'Metadata.appintents/extract.actionsdata').read_text())
assert set(metadata['actions']) == {'TranslateScreenshotIntent', 'TranslateTextIntent', 'TranslateScreenshotDocumentIntent'}
assert len(metadata['autoShortcuts']) == 1
assert metadata['actions']['TranslateScreenshotIntent']['isDiscoverable'] is False
for action in metadata['actions'].values():
    mode = next(p for p in action['parameters'] if p['name'] == 'mode')
    assert mode['valueType']['linkEnumeration']['wrapper']['identifier'] == 'ShortcutTranslationMode'
    assert {'string': {'wrapper': 'saved'}} in mode['typeSpecificMetadata']

args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as package:
    for p in sorted(app.rglob('*')):
        if p.is_file():
            assert not p.is_symlink(), 'Unexpected symbolic link in app bundle'
            package.write(p, str(Path('Payload') / app.name / p.relative_to(app)))
with zipfile.ZipFile(args.output) as package:
    assert package.testzip() is None
    names = package.namelist()
    assert all(name.startswith('Payload/ScreenTranslate.app/') for name in names)
    assert 'Payload/ScreenTranslate.app/Info.plist' in names
    assert 'Payload/ScreenTranslate.app/' + executable.name in names
    packed_info = plistlib.loads(package.read('Payload/ScreenTranslate.app/Info.plist'))
    assert packed_info == info
report = {
    'file': args.output.name,
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
    'bundleIdentifier': info['CFBundleIdentifier'],
    'bundleName': info['CFBundleName'],
    'localizedDisplayNames': localized_names,
    'minimumOSVersion': info['MinimumOSVersion'],
    'platform': info['DTPlatformName'],
    'architecture': architecture,
    'signature': 'Unsigned: codesign confirms all bundled Mach-O objects are not signed',
    'embeddedProvisioningProfile': False,
    'debugAndSimulationCode': 'Excluded',
    'appIntents': sorted(metadata['actions']),
    'zipCRC': 'Valid',
    'bytes': args.output.stat().st_size,
    'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
}
report_path = args.output.with_suffix('.verification.json')
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
