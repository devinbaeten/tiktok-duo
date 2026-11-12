#!/usr/bin/env python3
"""Build shareable archives from an explicit public-file allowlist."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '1.0.1'
NAME = f'TikTok-Duo-{VERSION}'
SCREENSHOTS = tuple(ROOT / f'docs/screenshots/{mode}.jpg' for mode in ('classic', 'native', 'fullscreen'))


def public_files():
    files = [ROOT / name for name in ('.gitignore', 'README.md', 'ARCHITECTURE.md', 'CHANGELOG.md', 'LICENSE', 'build.sh')]
    extensions = {'.m', '.h', '.c', '.sh', '.py', '.plist', '.yml'}
    for folder in ('src', 'tests', 'resources', 'scripts', '.github'):
        for path in (ROOT / folder).rglob('*'):
            if not path.is_file() or '__pycache__' in path.parts:
                continue
            if path.suffix not in extensions or path.is_symlink():
                raise ValueError(f'Unexpected public source file: {path.relative_to(ROOT)}')
            files.append(path)
    for path in files:
        text = path.read_text()
        if re.search(r'/Users/[A-Za-z0-9_]|/private/var/[A-Za-z0-9_]|000081[0-9A-F]{2}-[0-9A-F]{16}', text):
            raise ValueError(f'Private path or device ID: {path.relative_to(ROOT)}')
        if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}', text):
            raise ValueError(f'Credential pattern: {path.relative_to(ROOT)}')
    for path in SCREENSHOTS:
        if path.is_symlink() or not path.is_file() or not path.read_bytes().startswith(b'\xff\xd8'):
            raise ValueError('Missing or invalid mode screenshot')
    return sorted(files + list(SCREENSHOTS))


def archive(path, items):
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as out:
        for source, name in items:
            out.write(source, arcname=name)
    with zipfile.ZipFile(path) as check:
        if check.testzip() is not None:
            raise ValueError('Archive CRC failure')


def main():
    files = public_files()
    library = ROOT / 'build/TikTokDuo.dylib'
    if not library.is_file():
        raise ValueError('Run ./build.sh first')
    subprocess.run(['codesign', '--verify', '--strict', str(library)], check=True)
    dependencies = subprocess.check_output(['otool', '-L', str(library)], text=True)
    for line in dependencies.splitlines()[1:]:
        dependency = line.strip().split(' (', 1)[0]
        if dependency != '@executable_path/Frameworks/TikTokDuo.dylib' and not dependency.startswith(('/System/Library/', '/usr/lib/')):
            raise ValueError('Unexpected library dependency')
    dest = ROOT / 'dist'
    dest.mkdir(exist_ok=True)
    source = dest / f'{NAME}-source.zip'
    extension = dest / f'{NAME}-extension.zip'
    archive(source, [(p, f'{NAME}/{p.relative_to(ROOT).as_posix()}') for p in files])
    items = [(library, 'TikTokDuo.dylib')]
    items += [(p, p.relative_to(ROOT/'resources').as_posix()) for p in (ROOT/'resources/Settings.bundle').glob('*.plist')]
    items += [(ROOT / name, name) for name in ('README.md', 'LICENSE', 'CHANGELOG.md')]
    items += [(p, p.relative_to(ROOT).as_posix()) for p in SCREENSHOTS]
    archive(extension, items)
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (source, extension)}
    (dest/'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in hashes.items()))
    (dest/'release.json').write_text(json.dumps({'version': VERSION, 'artifacts': hashes,
        'source_files': len(files), 'device_validation': 'standalone pending'}, indent=2)+'\n')
    print(json.dumps({'source_files': len(files), 'artifacts': hashes}, indent=2))


if __name__ == '__main__':
    main()
