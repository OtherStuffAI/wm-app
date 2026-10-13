import importlib.util
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'ios/package_ambulando.py'
spec = importlib.util.spec_from_file_location('package_ambulando', MODULE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class BundleValidation(unittest.TestCase):
    def test_digest_binds_paths_and_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'index.html').write_text('fixture')
            before = module.tree_digest(root)[0]
            (root / 'index.html').rename(root / 'other.html')
            self.assertNotEqual(before, module.tree_digest(root)[0])
            (root / 'other.html').rename(root / 'index.html')
            self.assertEqual(before, module.tree_digest(root)[0])
            (root / 'index.html').write_text('changed')
            self.assertNotEqual(before, module.tree_digest(root)[0])

    def test_symlink_rejected_and_mismatch_cannot_replace_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'index.html').write_text('fixture')
            with self.assertRaisesRegex(ValueError, 'approved digest'):
                module.package(root, 'wrong')
            (root / 'linked.html').symlink_to(root / 'index.html')
            with self.assertRaisesRegex(ValueError, 'symlinks'):
                module.tree_digest(root)

if __name__ == '__main__':
    unittest.main()
