import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('nightly', Path(__file__).parents[1] / 'ios/nightly_testflight.py')
n = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(n)


class NightlyTests(unittest.TestCase):
    old = {'wmapp': 'a' * 40, 'flightdeck': 'b' * 40}
    new = {'wmapp': 'c' * 40, 'flightdeck': 'd' * 40}

    def test_duplicate_and_overlap_fail_closed_even_same_owner(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            n.transition(path, 'claim', 'a', '2026-10-06', source=self.old)
            for owner, day in [('a', '2026-10-06'), ('b', '2026-10-06'), ('b', '2026-10-07')]:
                with self.assertRaises(ValueError):
                    n.transition(path, 'claim', owner, day, source=self.new)

    def test_owner_finish_and_next_day(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            n.transition(path, 'claim', 'a', '2026-10-06', source=self.old)
            with self.assertRaises(ValueError):
                n.transition(path, 'finish', 'b', '2026-10-06', 'testing')
            n.transition(path, 'finish', 'a', '2026-10-06', 'blocked_auth')
            with self.assertRaises(ValueError):
                n.transition(path, 'claim', 'a', '2026-10-06', source=self.old)
            self.assertEqual(n.transition(path, 'claim', 'b', '2026-10-07', source=self.old)['status'], 'active')

    def test_19_october_failed_recovery_does_not_suppress_newer_scheduled_source(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            n.transition(path, 'claim', 'manual', '2026-10-19', source=self.old)
            n.transition(path, 'finish', 'manual', '2026-10-19', 'failed')
            with patch.object(n.dt, 'datetime', wraps=n.dt.datetime) as clock:
                clock.now.return_value = n.dt.datetime(2026, 10, 19, 18, tzinfo=n.ZoneInfo('Australia/Perth'))
                n.recover_claim(path, 'recovery', 'manual', 'retained-build-13', 'e' * 64)
            n.transition(path, 'finish', 'recovery', '2026-10-19', 'action_required')
            with self.assertRaisesRegex(ValueError, 'exact committed source'):
                n.transition(path, 'claim', 'scheduled', '2026-10-19', source=self.old)
            got = n.transition(path, 'claim', 'scheduled', '2026-10-19', source=self.new)
            self.assertEqual(got['attempt'], 3)
            self.assertEqual(got['source'], self.new)
            ledger = n._ledger(__import__('json').loads((path / 'ledger.json').read_text()))
            self.assertEqual([a['owner'] for a in ledger['days']['2026-10-19']['attempts']],
                             ['manual', 'recovery', 'scheduled'])

    def test_processing_and_testing_same_source_never_duplicate(self):
        for result in ('processing', 'testing'):
            with self.subTest(result=result), tempfile.TemporaryDirectory() as temp:
                path = Path(temp)
                n.transition(path, 'claim', 'a', '2026-10-19', source=self.old)
                n.transition(path, 'finish', 'a', '2026-10-19', result)
                with self.assertRaisesRegex(ValueError, 'exact committed source'):
                    n.transition(path, 'claim', 'b', '2026-10-19', source=self.old)

    def test_legacy_same_day_without_source_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp); path.mkdir(exist_ok=True)
            (path / 'ledger.json').write_text('{"schema":1,"days":{"2026-10-19":{"owner":"old","status":"failed"}}}')
            with self.assertRaisesRegex(ValueError, 'legacy claim'):
                n.transition(path, 'claim', 'new', '2026-10-19', source=self.new)

    def test_no_owner_or_fabricated_outcome(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            with self.assertRaises(ValueError):
                n.transition(path, 'claim', '', '2026-10-06', source=self.old)
            n.transition(path, 'claim', 'a', '2026-10-06', source=self.old)
            with self.assertRaises(ValueError):
                n.transition(path, 'finish', 'a', '2026-10-06', 'success')

    def test_private_path_rejects_outside_and_symlink(self):
        with self.assertRaises(ValueError):
            n.safe_private(n.ROOT / 'docs/release.json')
        with tempfile.TemporaryDirectory() as temp:
            link = Path(temp) / 'link'
            link.symlink_to(n.PRIVATE)
            with self.assertRaises(ValueError):
                n.safe_private(link)

    def test_ledger_symlink_cannot_overwrite_other_evidence(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            evidence = path / 'receipt.json'
            evidence.write_text('preserve')
            (path / 'ledger.json').symlink_to(evidence)
            with self.assertRaises(ValueError):
                n.transition(path, 'claim', 'a', '2026-10-06', source=self.old)
            self.assertEqual(evidence.read_text(), 'preserve')
