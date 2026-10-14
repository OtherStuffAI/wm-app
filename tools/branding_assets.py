#!/usr/bin/env python3
"""Reproduce approved WMApp raster exports with ImageMagick 7; --check audits them."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import struct

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / 'app/assets/branding/wayfinder-hybrid.png'
EXPORTS = {}

def add(path, size, maskable=False):
    EXPORTS[path] = (size, maskable)

for base in ('public', 'app/web'):
    for size in (16, 32, 48):
        add(f'{base}/favicon-{size}.png', size)
    add(f'{base}/favicon.png', 32)
    add(f'{base}/apple-touch-icon.png', 180)
    for size in (192, 512):
        add(f'{base}/icons/Icon-{size}.png', size)
        add(f'{base}/icons/Icon-maskable-{size}.png', size, True)
for suffix, size in [('', 60), ('@2x', 120), ('@3x', 180)]:
    add(f'app/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png', size)
add('public/logo.png', 512)
add('app/assets/branding/wmapp-logo.png', 512)
add('app/linux/runner/resources/wmapp.png', 256)
for platform in ('macos', 'ios'):
    folder = f'app/{platform}/Runner/Assets.xcassets/AppIcon.appiconset'
    for entry in json.loads((ROOT / folder / 'Contents.json').read_text())['images']:
        size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
        add(f"{folder}/{entry['filename']}", size)
for density, size in [('mdpi',48), ('hdpi',72), ('xhdpi',96), ('xxhdpi',144), ('xxxhdpi',192)]:
    add(f'app/android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)


def render(path, size, maskable):
    # The full approved square is reduced to 70% for maskable exports. The
    # coloured mark then stays inside the central 80%-diameter safe circle.
    inner = round(size * .70) if maskable else size
    subprocess.run(['magick', str(MASTER), '-resize', f'{inner}x{inner}',
                    '-background', 'white', '-alpha', 'remove', '-alpha', 'off',
                    '-gravity', 'center', '-extent', f'{size}x{size}',
                    '-strip', 'PNG24:' + str(path)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Compare each export and audit dimensions and references without writing assets')
    args = parser.parse_args()
    failures = []
    with tempfile.TemporaryDirectory(prefix='wmapp-branding-') as temp:
        for relative, (size, maskable) in EXPORTS.items():
            target = ROOT / relative
            output = Path(temp) / 'export.png' if args.check else target
            output.parent.mkdir(parents=True, exist_ok=True)
            render(output, size, maskable)
            if args.check and (not target.exists() or output.read_bytes() != target.read_bytes()):
                failures.append(relative)
            data = target.read_bytes()
            assert data[:8] == b'\x89PNG\r\n\x1a\n', relative
            width, height, depth, colour = struct.unpack('>IIBB', data[16:26])
            assert (width, height, depth, colour) == (size, size, 8, 2), relative
            if maskable:
                pixels = subprocess.check_output(['magick', str(target), '-depth', '8', 'RGB:-'])
                for offset in range(0, len(pixels), 3):
                    red, green, blue = pixels[offset:offset+3]
                    coloured = (red < 180 and blue > red + 30) or (red > 180 and green < 200 and blue < 150)
                    if coloured:
                        index = offset // 3
                        x, y = index % size, index // size
                        assert ((x + .5 - size / 2) ** 2 + (y + .5 - size / 2) ** 2) ** .5 <= size * .4, relative
            print(f'{relative}: PNG RGB {size}x{size}' + (' maskable safe padding' if maskable else ''))
        for base in ('public', 'app/web'):
            target = ROOT / base / 'favicon.ico'
            output = Path(temp) / 'favicon.ico' if args.check else target
            subprocess.run(['magick', *[str(ROOT / base / f'favicon-{s}.png') for s in (16,32,48)], str(output)], check=True)
            if args.check and (not target.exists() or output.read_bytes() != target.read_bytes()):
                failures.append(str(target.relative_to(ROOT)))
            frames = subprocess.check_output(['magick', 'identify', '-format', '%wx%h ', str(target)], text=True)
            assert frames.strip() == '16x16 32x32 48x48', frames
            print(f'{base}/favicon.ico: ICO 16/32/48')
            manifest = json.loads((ROOT / base / 'manifest.json').read_text())
            for icon in manifest['icons']:
                dims = subprocess.check_output(['magick', 'identify', '-format', '%wx%h', str(ROOT / base / icon['src'])], text=True)
                assert dims == icon['sizes'], (icon, dims)
                assert icon['type'] == 'image/png', icon
                assert icon.get('purpose', 'any') == ('maskable' if 'maskable' in icon['src'] else 'any'), icon
            html = (ROOT / base / 'index.html').read_text() if base == 'app/web' else ''
            for reference in ('favicon.ico', 'favicon-32.png', 'apple-touch-icon.png', 'manifest.json'):
                if html:
                    assert reference in html, reference
        for platform in ('ios','macos'):
            folder = ROOT / f'app/{platform}/Runner/Assets.xcassets/AppIcon.appiconset'
            for entry in json.loads((folder / 'Contents.json').read_text())['images']:
                assert (folder / entry['filename']).exists()
    print('Master SHA256:', hashlib.sha256(MASTER.read_bytes()).hexdigest())
    if failures:
        raise SystemExit('Stale or missing exports: ' + ', '.join(failures))
    print(f'PASS: {len(EXPORTS)} PNG exports, 2 ICO containers, manifest and Apple catalog references')

if __name__ == '__main__':
    main()
