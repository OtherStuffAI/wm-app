"""Release safety tests: no Flutter, Apple network calls, signing or uploads."""
import argparse
import contextlib
import io
import os
import subprocess
import time
import datetime as dt
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'ios/testflight_release.py')
r = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(r)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.s = {'schema': 1, 'version': '0.1.7', 'build': 9, 'stage': 'initialized', 'app_id': '123'}
        self.o = {'observed_at': r.now(), 'xcode_gui_account_present': True,
                  'team': r.TEAM, 'bundle': r.BUNDLE, 'app_id': '123',
                  'existing_builds': [8], 'history_complete': True, 'latest_version': '0.1.6',
                  'group': r.GROUP, 'internal': True, 'tester_count': 1, 'sole_tester_is_pete': True,
                  'public_link': False, 'other_distribution_groups': [], 'automatic_distribution_reviewed': True}
        self.b = dict(self.o, version='0.1.7', build=9, receipt_or_build_id='apple-build-id',
                      processing='complete', encryption_compliance='complete', assigned_to_group=True,
                      internal_only=True, pete_sees_exact_build=True)

    def test_preflight_and_no_accounts_is_not_logout(self):
        self.o['cli_error'] = 'No Accounts'
        r.preflight(self.o, self.s)
        self.assertIn('does not mean Xcode is signed out', r.ACCOUNT_HELP)

    def test_missing_gui_account_fails(self):
        self.o['xcode_gui_account_present'] = False
        with self.assertRaisesRegex(ValueError, 'existing account'):
            r.preflight(self.o, self.s)

    def test_team_and_bundle_mismatch(self):
        for key in ['team', 'bundle']:
            with self.subTest(key=key):
                o = dict(self.o, **{key: 'wrong'})
                with self.assertRaises(ValueError):
                    r.preflight(o, self.s)

    def test_duplicate_and_older_build(self):
        for build in [8, 7, 9]:
            with self.subTest(build=build):
                with self.assertRaisesRegex(ValueError, 'Duplicate'):
                    r.preflight(dict(self.o, existing_builds=[8, 9]), dict(self.s, build=build))

    def test_incomplete_history(self):
        with self.assertRaisesRegex(ValueError, 'all iOS build history'):
            r.preflight(dict(self.o, history_complete=False), self.s)

    def test_old_version(self):
        with self.assertRaisesRegex(ValueError, 'older'):
            r.preflight(dict(self.o, latest_version='0.2.0'), self.s)

    def test_stale_observation(self):
        with self.assertRaisesRegex(ValueError, '24 hours'):
            r.preflight(dict(self.o, observed_at='2020-01-01T00:00:00+00:00'), self.s)

    def test_audience_drift(self):
        for change in [dict(tester_count=2), dict(sole_tester_is_pete=False), dict(group='Other'),
                       dict(public_link=True), dict(other_distribution_groups=['Other']), dict(internal=False)]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                r.preflight(dict(self.o, **change), self.s)

    def test_upload_processing_and_ready_are_distinct(self):
        self.assertEqual(r.readback(dict(self.b, processing='processing'), self.s), 'uploaded_processing')
        self.assertEqual(r.readback(dict(self.b, processing='failed'), self.s), 'uploaded_action_required')
        self.assertEqual(r.readback(dict(self.b, encryption_compliance='pending'), self.s), 'uploaded_action_required')
        self.assertEqual(r.readback(dict(self.b, pete_sees_exact_build=False), self.s), 'processed_awaiting_tester')
        self.assertEqual(r.readback(self.b, self.s), 'ready_to_test')

    def test_no_receipt_or_wrong_build_never_ready(self):
        for change in [dict(receipt_or_build_id=None), dict(build=8), dict(app_id='456'),
                       dict(assigned_to_group=False), dict(internal_only=False), dict(tester_count=2)]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                r.readback(dict(self.b, **change), self.s)

    def test_stale_ipa(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            (run / 'Runner.xcarchive').mkdir()
            (run / 'export').mkdir()
            (run / 'export/stale.ipa').write_bytes(b'old')
            s = dict(self.s, archive_hashes={}, export_started_ns=10**30)
            with patch.object(r, 'signed_app'), self.assertRaisesRegex(ValueError, 'Stale IPA'):
                r.validate_artifacts(run, s)

    def test_changed_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            (run / 'Runner.xcarchive').mkdir()
            (run / 'Runner.xcarchive/file').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'Archive changed'):
                r.validate_artifacts(run, dict(self.s, archive_hashes={}))

    def test_profile_validation_both_targets(self):
        for bundle in [r.BUNDLE, r.BUNDLE + '.FipsPacketTunnel']:
            info = dict(CFBundleIdentifier=bundle, CFBundleShortVersionString='0.1.7', CFBundleVersion='9')
            ent = {'application-identifier': r.TEAM + '.' + bundle,
                   'com.apple.developer.team-identifier': r.TEAM, 'get-task-allow': False,
                   'beta-reports-active': True, 'com.apple.developer.networking.networkextension': ['packet-tunnel-provider']}
            profile = {'TeamIdentifier': [r.TEAM], 'ExpirationDate': dt.datetime.now() + dt.timedelta(days=1), 'Entitlements': ent}
            r.profile_check(info, profile, ent, self.s, bundle)
            for key, value in [('ProvisionedDevices', ['generic-device']), ('TeamIdentifier', ['WRONG'])]:
                with self.subTest(bundle=bundle, key=key), self.assertRaises(ValueError):
                    r.profile_check(info, dict(profile, **{key: value}), ent, self.s, bundle)
            for change in [{'get-task-allow': True}, {'application-identifier': 'wrong'},
                           {'com.apple.developer.networking.networkextension': []}]:
                with self.subTest(change=change), self.assertRaises(ValueError):
                    r.profile_check(info, profile, dict(ent, **change), self.s, bundle)
            with self.assertRaisesRegex(ValueError, 'stale artifact'):
                r.profile_check(dict(info, CFBundleVersion='8'), profile, ent, self.s, bundle)

    def test_dry_run_no_build_or_state_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            r.write(run / 'state.json', self.s)
            r.write(run / 'preflight.json', self.o)
            before = (run / 'state.json').read_bytes()
            with patch.object(r, 'logged') as log, patch.object(r, 'command') as cmd:
                r.execute(argparse.Namespace(action='run', dry_run=True), run)
            log.assert_not_called()
            cmd.assert_not_called()
            self.assertEqual(before, (run / 'state.json').read_bytes())

    def test_upload_pending_barrier_prevents_repeat(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            s = dict(self.s, stage='exported', artifact={'sha256': 'exact-ipa'})
            r.write(run / 'state.json', s)
            r.write(run / 'preflight.json', self.o)
            with patch.object(r, 'validate_artifacts', return_value=s['artifact']), patch.object(r, 'logged') as log:
                r.execute(argparse.Namespace(action='upload'), run)
                log.assert_not_called()
            self.assertEqual(r.read(run / 'state.json')['stage'], 'upload_pending')
            with self.assertRaisesRegex(ValueError, 'pending or performed'):
                r.execute(argparse.Namespace(action='upload'), run)

    def test_ipa_cannot_establish_uploaded_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            r.write(run / 'state.json', dict(self.s, stage='exported'))
            with self.assertRaisesRegex(ValueError, 'IPA is not evidence'):
                r.execute(argparse.Namespace(action='readback'), run)

    def test_preserve_existing_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run = root / 'run'
            run.mkdir()
            output = root / 'app/build/ios/archive'
            output.mkdir(parents=True)
            (output / 'record').write_bytes(b'original\x00bytes')
            with patch.object(r, 'ROOT', root):
                r.preserve_outputs(run)
            self.assertEqual((run / 'previous-archive/record').read_bytes(), b'original\x00bytes')
            self.assertEqual(r.read(run / 'previous-archive-hashes.json'), r.tree_hash(run / 'previous-archive'))

    def test_cli_no_accounts_error_gives_gui_recovery(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = io.StringIO()
            def failed(args, stdout, stderr):
                stdout.write(b'error: No Accounts\n')
                return subprocess.CompletedProcess(args, 1)
            with patch.object(r.subprocess, 'run', side_effect=failed), contextlib.redirect_stdout(output):
                with self.assertRaisesRegex(ValueError, 'No upload'):
                    r.logged(['xcodebuild'], Path(tmp), 'export')
            self.assertIn('does not mean Xcode is signed out', output.getvalue())
            self.assertIn('Organizer', output.getvalue())

    def test_failed_build_export_retains_archive_and_resumes_without_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run = root / 'run'
            run.mkdir()
            r.write(run / 'state.json', self.s)
            r.write(run / 'preflight.json', self.o)
            source = root / 'app/build/ios/archive/Runner.xcarchive'
            def build_failed(*args):
                source.mkdir(parents=True)
                (source / 'record').write_bytes(b'archive')
                future = time.time_ns() + 1000000
                os.utime(source, ns=(future, future))
                raise ValueError('No Accounts')
            with patch.object(r, 'ROOT', root), patch.object(r, 'project_settings'), \
                 patch.object(r, 'command'), patch.object(r, 'logged', side_effect=build_failed):
                with self.assertRaisesRegex(ValueError, 'No Accounts'):
                    r.execute(argparse.Namespace(action='run', dry_run=False), run)
            self.assertEqual(r.read(run / 'state.json')['stage'], 'archived')
            self.assertEqual((run / 'Runner.xcarchive/record').read_bytes(), b'archive')
            with patch.object(r, 'ROOT', root), patch.object(r, 'project_settings'), \
                 patch.object(r, 'command'), patch.object(r, 'signed_app'), \
                 patch.object(r, 'validate_artifacts', return_value={'sha256': 'new'}), \
                 patch.object(r, 'logged') as logged:
                r.execute(argparse.Namespace(action='run', dry_run=False), run)
                args = logged.call_args.args[0]
                self.assertEqual(args[0], 'xcodebuild')
                self.assertIn(run / 'Runner.xcarchive', args)
            self.assertEqual(r.read(run / 'state.json')['stage'], 'exported')

    def test_changed_ipa_blocks_upload(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            r.write(run / 'state.json', dict(self.s, stage='exported', artifact={'sha256': 'original'}))
            r.write(run / 'preflight.json', self.o)
            with patch.object(r, 'validate_artifacts', return_value={'sha256': 'changed'}):
                with self.assertRaisesRegex(ValueError, 'IPA changed'):
                    r.execute(argparse.Namespace(action='upload'), run)
            self.assertEqual(r.read(run / 'state.json')['stage'], 'exported')

    def test_cli_upload_pins_policy_and_never_claims_delivery(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            s = dict(self.s, stage='exported', artifact={'sha256': 'exact-ipa'})
            r.write(run / 'state.json', s)
            r.write(run / 'preflight.json', self.o)
            def upload(args, observed_run, label):
                # Barrier must exist before the network-capable command starts.
                self.assertEqual(r.read(run / 'state.json')['stage'], 'upload_pending')
                self.assertEqual(label, 'upload')
                self.assertEqual(args[0], 'xcodebuild')
                self.assertIn(run / 'Runner.xcarchive', args)
                self.assertIn('-allowProvisioningUpdates', args)
                options = r.plistlib.loads((run / 'UploadOptions.plist').read_bytes())
                self.assertEqual(options['destination'], 'upload')
                self.assertEqual(options['teamID'], r.TEAM)
                self.assertIs(options['testFlightInternalTestingOnly'], True)
                self.assertIs(options['manageAppVersionAndBuildNumber'], False)
            with patch.object(r, 'validate_artifacts', return_value=s['artifact']), \
                 patch.object(r, 'logged', side_effect=upload) as logged:
                r.execute(argparse.Namespace(action='upload', via='cli'), run)
                logged.assert_called_once()
            result = r.read(run / 'state.json')
            self.assertEqual(result['stage'], 'upload_pending')
            self.assertIn('cli_upload_command_completed_at', result)
            self.assertNotIn('apple_readback', result)

    def test_failed_cli_upload_is_uncertain_and_cannot_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            s = dict(self.s, stage='exported', artifact={'sha256': 'exact-ipa'})
            r.write(run / 'state.json', s)
            r.write(run / 'preflight.json', self.o)
            def failed(args, stdout, stderr):
                self.assertEqual(r.read(run / 'state.json')['stage'], 'upload_pending')
                stdout.write(b'No Accounts')
                return subprocess.CompletedProcess(args, 1)
            with patch.object(r, 'validate_artifacts', return_value=s['artifact']), \
                 patch.object(r.subprocess, 'run', side_effect=failed) as command:
                with self.assertRaisesRegex(ValueError, 'Upload outcome uncertain'):
                    r.execute(argparse.Namespace(action='upload', via='cli'), run)
                with self.assertRaisesRegex(ValueError, 'pending or performed'):
                    r.execute(argparse.Namespace(action='upload', via='cli'), run)
                command.assert_called_once()
            self.assertEqual(r.read(run / 'state.json')['stage'], 'upload_pending')
            self.assertNotIn('cli_upload_command_completed_at', r.read(run / 'state.json'))

    def test_second_run_cannot_retry_uncertain_delivery(self):
        with tempfile.TemporaryDirectory() as tmp:
            private = Path(tmp)
            other = private / 'other'
            other.mkdir()
            r.write(other / 'state.json', dict(self.s, stage='upload_pending'))
            with patch.object(r, 'PRIVATE', private):
                with self.assertRaisesRegex(ValueError, 'Another run'):
                    r.no_other_delivery(private / 'new', self.s)
                r.no_other_delivery(other, self.s)
                r.no_other_delivery(private / 'new', dict(self.s, build=10))

    def test_successful_helper_ipa_is_reused_without_second_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run = root / 'run'
            run.mkdir()
            r.write(run / 'state.json', self.s)
            r.write(run / 'preflight.json', self.o)
            def build(args, observed_run, label):
                self.assertEqual(args, [root / 'build_ios_testflight.sh', '--build-name=0.1.7', '--build-number=9'])
                archive = root / 'app/build/ios/archive/Runner.xcarchive'
                archive.mkdir(parents=True)
                ipa_dir = root / 'app/build/ios/ipa'
                ipa_dir.mkdir()
                (ipa_dir / 'fresh.ipa').write_bytes(b'new signed fixture')
                future = time.time_ns() + 1000000
                os.utime(archive, ns=(future, future))
            with patch.object(r, 'ROOT', root), patch.object(r, 'project_settings'), \
                 patch.object(r, 'command'), patch.object(r, 'logged', side_effect=build) as logged, \
                 patch.object(r, 'validate_artifacts', return_value={'sha256': 'fresh'}):
                r.execute(argparse.Namespace(action='run', dry_run=False), run)
                logged.assert_called_once()
            self.assertEqual((run / 'export/fresh.ipa').read_bytes(), b'new signed fixture')
            self.assertEqual(r.read(run / 'state.json')['stage'], 'exported')

    def test_repository_options_and_settings(self):
        r.options()
        r.project_settings()


if __name__ == '__main__':
    unittest.main()
