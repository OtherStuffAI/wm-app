#!/usr/bin/env python3
"""Copy an explicitly selected validated Sol dist, verifying its tree digest."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'app/assets/ambulando'

def tree_digest(root):
    files = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError('Bundle must not contain symlinks')
        if path.is_file():
            files[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    encoded = json.dumps(files, sort_keys=True, separators=(',', ':')).encode()
    return hashlib.sha256(encoded).hexdigest(), files

def package(source, expected):
    source = source.resolve(strict=True)
    if source == DEST.resolve() or not (source / 'index.html').is_file():
        raise ValueError('Select a Sol dist with index.html')
    digest, files = tree_digest(source)
    if digest != expected:
        raise ValueError('Sol dist changed or does not match the approved digest')
    # Flutter lists asset directories explicitly. New product directories require
    # a reviewed pubspec change rather than silently producing missing resources.
    pubspec = (ROOT / 'app/pubspec.yaml').read_text()
    for name in files:
        parent = Path(name).parent.as_posix()
        directory = 'assets/ambulando/' + (parent + '/' if parent != '.' else '')
        if f'    - path: {directory}\n' not in pubspec:
            raise ValueError(f'Add bundle directory to pubspec: {directory}')
    stage = DEST.with_name('ambulando-staging')
    if stage.exists():
        shutil.rmtree(stage)
    shutil.copytree(source, stage)
    if tree_digest(stage)[0] != digest or tree_digest(source)[0] != digest:
        shutil.rmtree(stage)
        raise ValueError('Bundle changed while copying')
    if DEST.exists():
        shutil.rmtree(DEST)
    stage.rename(DEST)
    return {'tree_sha256': digest, 'file_count': len(files)}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dist', type=Path)
    parser.add_argument('--expected-sha256')
    parser.add_argument('--inspect', action='store_true')
    args = parser.parse_args()
    if args.inspect:
        digest, files = tree_digest(args.dist)
        print(json.dumps({'tree_sha256': digest, 'file_count': len(files)}))
    elif not args.expected_sha256:
        parser.error('--expected-sha256 is required for packaging')
    else:
        print(json.dumps(package(args.dist, args.expected_sha256)))
