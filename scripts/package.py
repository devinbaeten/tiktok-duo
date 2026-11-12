#!/usr/bin/env python3
"""Inject the standalone library into a user-supplied, decrypted TikTok IPA.
No app downloads, signing credentials, or proprietary artifacts are included.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import uuid
import zipfile

VERSION = ('47.7.0', '477034')
CORE_UUID = uuid.UUID('81156393-0f58-38c4-8723-0b15cf11ec16').bytes
LOAD_PATH = b'@executable_path/Frameworks/TikTokDuo.dylib'
DEST = 'Payload/TikTok.app/Frameworks/TikTokDuo.dylib'
APP = 'Payload/TikTok.app/'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def commands(data):
    require(len(data) >= 32, 'Truncated Mach-O header')
    magic, cpu = struct.unpack_from('<II', data)
    require(magic == 0xfeedfacf and cpu == 0x100000c, 'Expected thin arm64 Mach-O')
    count, size = struct.unpack_from('<II', data, 16)
    end = 32 + size
    require(end <= len(data), 'Truncated Mach-O commands')
    offset = 32
    result = []
    for _ in range(count):
        require(offset + 8 <= end, 'Truncated load command')
        cmd, length = struct.unpack_from('<II', data, offset)
        require(length >= 8 and offset + length <= end, 'Invalid load command length')
        result.append((cmd, offset, length))
        offset += length
    require(offset == end, 'Load command size mismatch')
    return result


def loaded_paths(data):
    result = []
    for cmd, offset, size in commands(data):
        if cmd in (0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023):
            require(size >= 24, 'Truncated dylib command')
            name_offset = struct.unpack_from('<I', data, offset + 8)[0]
            require(24 <= name_offset < size, 'Invalid dylib name offset')
            result.append(data[offset + name_offset:offset + size].split(b'\0', 1)[0])
    return result


def require_decrypted(data):
    for cmd, offset, size in commands(data):
        if cmd in (0x21, 0x2c):
            require(size >= 20, 'Truncated encryption command')
            require(struct.unpack_from('<I', data, offset + 16)[0] == 0,
                    'Encrypted Mach-O: supply your own decrypted IPA')


def add_load(data):
    require_decrypted(data)
    require(LOAD_PATH not in loaded_paths(data), 'Extension already injected')
    first = None
    for cmd, offset, size in commands(data):
        if cmd != 0x19:
            continue
        require(size >= 72, 'Truncated segment command')
        nsects = struct.unpack_from('<I', data, offset + 64)[0]
        require(72 + 80 * nsects <= size, 'Truncated section records')
        for i in range(nsects):
            file_offset = struct.unpack_from('<I', data, offset + 72 + i * 80 + 48)[0]
            if file_offset:
                first = min(first or file_offset, file_offset)
    count, size = struct.unpack_from('<II', data, 16)
    start = 32 + size
    name = LOAD_PATH + b'\0'
    length = (24 + len(name) + 7) & ~7
    require(first is not None and start + length <= first <= len(data),
            'Insufficient Mach-O header padding')
    require(not any(data[start:start + length]), 'Header padding is not empty')
    out = bytearray(data)
    command = struct.pack('<IIIIII', 0xc, length, 24, 0, 0, 0) + name
    out[start:start + length] = command.ljust(length, b'\0')
    struct.pack_into('<II', out, 16, count + 1, size + length)
    return bytes(out)


def prepare(ipa, dylib, output, settings):
    ipa, dylib, output, settings = map(Path, (ipa, dylib, output, settings))
    require(not output.exists(), 'Output already exists; choose a new path')
    library = dylib.read_bytes()
    require(struct.unpack_from('<I', library, 12)[0] == 6, 'Expected a Mach-O dylib')
    commands(library)
    require_decrypted(library)
    require(all(p.startswith((b'/System/Library/', b'/usr/lib/')) for p in loaded_paths(library)),
            'Extension dependencies must be Apple system libraries')
    resources = {f.relative_to(settings).as_posix(): f.read_bytes()
                 for f in settings.rglob('*') if f.is_file()}
    require({'Root.plist', 'Advanced.plist', 'Diagnostics.plist'} <= resources.keys(),
            'Missing Settings.bundle pages')
    for name, content in resources.items():
        require(name.endswith('.plist'), 'Unexpected Settings.bundle resource')
        plistlib.loads(content)
    with zipfile.ZipFile(ipa) as source:
        names = source.namelist()
        require(len(names) == len(set(names)), 'Duplicate ZIP members')
        require(source.testzip() is None, 'Invalid source ZIP CRC')
        require(not any(n.endswith('.dylib') for n in names),
                'Use a clean TikTok IPA without added dynamic libraries')
        require(DEST not in names, 'Extension already present')
        require(not any(n.startswith(APP + 'Settings.bundle/') for n in names),
                'Existing Settings.bundle would be overwritten; use a clean IPA')
        info = plistlib.loads(source.read(APP + 'Info.plist'))
        require((info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')) == VERSION,
                'Only TikTok 47.7.0 build 477034 is supported')
        require(info.get('CFBundleIdentifier') == 'com.zhiliaoapp.musically', 'Unexpected app bundle ID')
        exe = info['CFBundleExecutable']
        require('/' not in exe and exe not in ('.', '..'), 'Invalid executable name')
        executable = APP + exe
        core = source.read(APP + 'Frameworks/MusicallyCore.framework/MusicallyCore')
        require_decrypted(core)
        uuids = [core[o+8:o+24] for cmd, o, size in commands(core) if cmd == 0x1b and size == 24]
        require(uuids == [CORE_UUID], 'Unsupported MusicallyCore UUID')
        patched = add_load(source.read(executable))
        with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as dest:
            for entry in source.infolist():
                if entry.filename == executable:
                    dest.writestr(entry, patched)
                else:
                    with source.open(entry) as reader, dest.open(entry, 'w', force_zip64=True) as writer:
                        while chunk := reader.read(1024 * 1024):
                            writer.write(chunk)
            item = zipfile.ZipInfo(DEST)
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = 0o100755 << 16
            dest.writestr(item, library)
            for name, content in resources.items():
                dest.writestr(APP + 'Settings.bundle/' + name, content)
    with zipfile.ZipFile(output) as result:
        require(result.testzip() is None, 'Output ZIP CRC failure')
        require(result.read(DEST) == library, 'Packaged library differs')
        require(LOAD_PATH in loaded_paths(result.read(executable)), 'Load command missing')
        for name, content in resources.items():
            require(result.read(APP + 'Settings.bundle/' + name) == content, 'Settings mismatch')
    digest = hashlib.sha256()
    with output.open('rb') as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    metadata = {'tiktok': VERSION[0], 'build': VERSION[1], 'sha256': digest.hexdigest(),
                'extension_sha256': hashlib.sha256(library).hexdigest(),
                'status': 'Packaging verified. Re-sign the whole app before installation. Runtime unverified.'}
    output.with_suffix(output.suffix + '.json').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', required=True, help='User-supplied clean, decrypted IPA')
    parser.add_argument('--dylib', default='build/TikTokDuo.dylib')
    parser.add_argument('--out', required=True, help='New output IPA path')
    parser.add_argument('--settings', default=str(Path(__file__).resolve().parents[1] / 'resources/Settings.bundle'))
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.ipa, args.dylib, args.out, args.settings), indent=2))
    except (ValueError, OSError, KeyError, struct.error, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.exit(1, f'Packaging failed: {error}\n')
