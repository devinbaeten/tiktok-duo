import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('package', ROOT / 'scripts/package.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


def macho(filetype=2, core=False, encrypted=False):
    segment = bytearray(152)
    struct.pack_into('<II', segment, 0, 0x19, 152)
    struct.pack_into('<I', segment, 64, 1)
    struct.pack_into('<I', segment, 72 + 48, 4096)
    cmds = bytes(segment)
    count = 1
    if core:
        cmds += struct.pack('<II', 0x1b, 24) + package.CORE_UUID
        count += 1
    if encrypted:
        cmds += struct.pack('<IIIIII', 0x2c, 24, 4096, 16, 1, 0)
        count += 1
    header = struct.pack('<IIIIIIII', 0xfeedfacf, 0x100000c, 0, filetype, count, len(cmds), 0, 0)
    return (header + cmds).ljust(4096, b'\0') + b'fixture contents'


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.ipa = self.folder / 'input.ipa'
        self.output = self.folder / 'output.ipa'
        self.dylib = self.folder / 'library.dylib'
        self.dylib.write_bytes(macho(6))
        self.settings = ROOT / 'resources/Settings.bundle'

    def make_ipa(self, **changes):
        info = {'CFBundleExecutable': 'TikTok', 'CFBundleShortVersionString': '47.7.0',
                'CFBundleVersion': '477034', 'CFBundleIdentifier': 'com.zhiliaoapp.musically'}
        info.update(changes.pop('info', {}))
        entries = {package.APP+'Info.plist': plistlib.dumps(info), package.APP+'TikTok': macho(),
                   package.APP+'Frameworks/MusicallyCore.framework/MusicallyCore': macho(core=True),
                   package.APP+'PlugIns/Example.appex/data': b'preserved extension',
                   package.APP+'Assets.car': b'preserved resource'}
        entries.update(changes)
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            for name, data in entries.items():
                archive.writestr(name, data)

    def prepare(self):
        return package.prepare(self.ipa, self.dylib, self.output, self.settings)

    def test_standalone_injection_and_preservation(self):
        self.make_ipa()
        result = self.prepare()
        self.assertEqual(len(result['sha256']), 64)
        with zipfile.ZipFile(self.output) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(package.loaded_paths(archive.read(package.APP+'TikTok')), [package.LOAD_PATH])
            self.assertEqual(archive.read(package.DEST), self.dylib.read_bytes())
            self.assertEqual(archive.read(package.APP+'PlugIns/Example.appex/data'), b'preserved extension')
            self.assertEqual(archive.read(package.APP+'Assets.car'), b'preserved resource')
            self.assertEqual(archive.read(package.APP+'Settings.bundle/Root.plist'), (self.settings/'Root.plist').read_bytes())
        with self.assertRaisesRegex(ValueError, 'already exists'):
            self.prepare()

    def test_unsupported_and_encrypted_inputs(self):
        variants = [
            {'info': {'CFBundleVersion': '999999'}},
            {'info': {'CFBundleIdentifier': 'com.example.other'}},
            {package.APP+'TikTok': macho(encrypted=True)},
            {package.APP+'Frameworks/MusicallyCore.framework/MusicallyCore': macho(core=True, encrypted=True)},
            {package.APP+'Frameworks/MusicallyCore.framework/MusicallyCore': macho(core=True).replace(package.CORE_UUID, b'\0'*16)},
            {package.APP+'Settings.bundle/Root.plist': b'existing settings'},
            {package.APP+'Frameworks/ExampleExtra.dylib': b'other tweak'},
            {package.DEST: b'already injected'},
        ]
        for variant in variants:
            with self.subTest(variant=list(variant)):
                self.make_ipa(**variant)
                with self.assertRaises(ValueError):
                    self.prepare()
                self.assertFalse(self.output.exists())

    def test_command_and_padding_guards(self):
        data = macho()
        patched = package.add_load(data)
        with self.assertRaisesRegex(ValueError, 'already injected'):
            package.add_load(patched)
        for data in (b'truncated', data[:40], data[:184]+b'x'+data[185:]):
            with self.subTest(length=len(data)):
                with self.assertRaises(ValueError):
                    package.add_load(data)

    def test_source_and_preference_boundaries(self):
        release_spec = importlib.util.spec_from_file_location('release', ROOT / 'scripts/release.py')
        release = importlib.util.module_from_spec(release_spec)
        release_spec.loader.exec_module(release)
        self.assertTrue(release.public_files())
        for path in self.settings.glob('*.plist'):
            data = plistlib.loads(path.read_bytes())
            for item in data['PreferenceSpecifiers']:
                if 'Key' in item:
                    self.assertTrue(item['Key'].startswith('TCLCover.'), item)


if __name__ == '__main__':
    unittest.main()
