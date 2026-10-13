import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('nightly',Path(__file__).resolve().parents[1]/'nightly_zapstore.py')
n=importlib.util.module_from_spec(spec);spec.loader.exec_module(n)
class NightlyTests(unittest.TestCase):
    def test_monotonic_over_local_and_remote(self):
        ledger={'schema':1,'runs':{'yesterday':{'stage':'published','version_code':2000000001}}}
        self.assertEqual(n.reserve(ledger,'today','session',2000000005,'2.3.4')['version_code'],2000000006)
    def test_source_marketing_version_is_not_hardcoded(self):
        s=n.reserve({'schema':1,'runs':{}},'2026-10-06','session',0,'2.3.4')
        self.assertTrue(s['version_name'].startswith('2.3.4-nightly.20261006.'))
        with self.assertRaises(ValueError):n.reserve({'schema':1,'runs':{}},'today','session',0,'invalid')
    def test_duplicate_and_uncertain_delivery_block(self):
        ledger={'schema':1,'runs':{}}
        n.reserve(ledger,'today','session',0,'2.3.4')
        with self.assertRaisesRegex(ValueError,'already'):n.reserve(ledger,'today','session',0,'2.3.4')
        for stage in ('reserved','building','built','prepared','prepared_public','public_assets_pending','delivery_pending','listing_update_pending'):
            ledger['runs']['today']['stage']=stage
            with self.assertRaisesRegex(ValueError,'uncertain'):n.reserve(ledger,'tomorrow','other',0,'2.3.4')
    def test_invalid_history_and_owner_fail_closed(self):
        for maximum in (-1,False,1.2,None):
            with self.assertRaises(ValueError):n.reserve({'schema':1,'runs':{}},'today','session',maximum,'2.3.4')
        with self.assertRaises(ValueError):n.reserve({'schema':1,'runs':{}},'today',None,0,'2.3.4')
    def test_version_limit(self):
        with self.assertRaises(ValueError):n.reserve({'schema':1,'runs':{}},'today','session',2100000000,'2.3.4')
    def test_same_owner_resume_refuses_signing_or_delivery(self):
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            run=Path(temp);s={'owner':'same','stage':'building'}
            n.require_resume(s,'same',run)
            with self.assertRaises(ValueError):n.require_resume(s,'other',run)
            for stage in ('built','prepared','prepared_public','delivery_pending','published'):
                with self.assertRaises(ValueError):n.require_resume({**s,'stage':stage},'same',run)
            (run/'proof-signed.json').write_text('{}')
            with self.assertRaises(ValueError):n.require_resume(s,'same',run)
    def test_independent_lane_preserves_retained_apple_claim(self):
        import tempfile,json
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();lock=root/'tmp/docs/handoffs/nightly-release-shared.lock';lock.mkdir(parents=True)
            (lock/'owner.json').write_text(json.dumps({'SESSION_ID':'android','store':'zapstore','day':'today'}))
            apple=root/'tmp/docs/handoffs/nightly-testflight/ledger.json';apple.parent.mkdir()
            original=b'{"schema":1,"days":{"yesterday":{"status":"active","owner":"apple","recovery_run":"retained"}}}\n'
            apple.write_bytes(original)
            with patch.object(n,'ROOT',root),patch.object(n.subprocess,'run'),patch.object(n,'command',return_value=''):
                n.require_shared_lock('android','today')
                self.assertEqual(n.reserve({'schema':1,'runs':{}},'today','android',0,'1.2.3')['stage'],'reserved')
            self.assertEqual(apple.read_bytes(),original)
    def test_shared_lock_requires_exact_owner_store_day_and_real_path(self):
        import tempfile,json
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp).resolve();lock=root/'tmp/docs/handoffs/nightly-release-shared.lock';lock.parent.mkdir(parents=True)
            with patch.object(n,'ROOT',root),patch.object(n.subprocess,'run'),patch.object(n,'command',return_value=''):
                with self.assertRaisesRegex(ValueError,'missing or busy'):n.require_shared_lock('android','today')
                lock.mkdir()
                with self.assertRaisesRegex(ValueError,'missing or busy'):n.require_shared_lock('android','today')
                record=lock/'owner.json'
                for state in ({'SESSION_ID':'apple','store':'testflight','day':'today'},
                              {'SESSION_ID':'android','store':'testflight','day':'today'},
                              {'SESSION_ID':'android','store':'zapstore','day':'yesterday'}):
                    record.write_text(json.dumps(state));before=record.read_bytes()
                    with self.assertRaisesRegex(ValueError,'another'):n.require_shared_lock('android','today')
                    self.assertEqual(record.read_bytes(),before)
                record.unlink();target=root/'foreign.json';target.write_text('{}');record.symlink_to(target)
                with self.assertRaisesRegex(ValueError,'missing or busy'):n.require_shared_lock('android','today')
                record.unlink();lock.rmdir();lock.symlink_to(root,target_is_directory=True)
                with self.assertRaisesRegex(ValueError,'Verified'):n.require_shared_lock('android','today')
    def test_build_checks_shared_lock_before_history_or_reservation(self):
        import tempfile,os,datetime
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp:
            private=Path(temp);day=n.dt.datetime.now(n.ZoneInfo('Australia/Perth')).date().isoformat()
            with patch.object(n,'PRIVATE',private),patch.object(n,'safe_private'),patch.object(n,'command') as command,patch.dict(os.environ,{'SESSION_ID':'android','FLIGHT_DECK_PG_APP_NPUB':'verified'}),patch.object(n.sys,'argv',['nightly','build','--day',day]),patch.object(n,'require_shared_lock',side_effect=ValueError('foreign shared lock')) as guard:
                with self.assertRaisesRegex(ValueError,'foreign shared lock'):n.main()
                guard.assert_called_once_with('android',day);command.assert_not_called()
                self.assertFalse((private/'ledger.json').exists())
    def test_inactive_flavor_assets_are_empty_and_pubspec_is_unchanged(self):
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            wm=Path(temp).resolve();(wm/'app').mkdir()
            pubspec=wm/'app/pubspec.yaml';original=(n.ROOT/'app/pubspec.yaml').read_bytes();pubspec.write_bytes(original)
            n.prepare_inactive_flavor_assets(wm)
            self.assertTrue((wm/'app/assets/ambulando/napplets/org-data/v1').is_dir())
            self.assertEqual(pubspec.read_bytes(),original)
            self.assertFalse(any(p.is_file() for p in (wm/'app/assets/ambulando').rglob('*')))
            self.assertFalse((wm/'app/assets/flightdeck').exists())
    def test_snapshot_has_real_source_index_and_preserves_shared_state(self):
        import tempfile,subprocess
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp:
            repo=Path(temp)/'source';repo.mkdir()
            def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],text=True).strip()
            git('init','-b','main');git('config','user.name','Test');git('config','user.email','test@example.invalid')
            (repo/'source.txt').write_text('committed source');git('add','source.txt');git('commit','-m','test: source')
            (repo/'unfinished.txt').write_text('concurrent edit')
            before=git('status','--porcelain')
            with patch.object(n,'safe_private',lambda p:None):commit=n.snapshot(repo,Path(temp)/'snapshot')
            self.assertEqual(git('status','--porcelain'),before)
            self.assertEqual(n.command(['git','ls-files'],Path(temp)/'snapshot'),'source.txt')
            self.assertEqual(n.command(['git','rev-parse','HEAD'],Path(temp)/'snapshot'),commit)
            self.assertFalse((Path(temp)/'snapshot/unfinished.txt').exists())
    def test_package_isolation_and_provider_scope(self):
        root=Path(__file__).resolve().parents[2]
        gradle=(root/'app/android/app/build.gradle.kts').read_text()
        self.assertIn('if (nightly) "'+n.PACKAGE+'" else "com.wingmanbefree.wingman_app"',gradle)
        manifest=(root/'app/android/app/src/main/AndroidManifest.xml').read_text()
        self.assertIn('${applicationId}.drivefiles',manifest)
        self.assertIn('com.wingmanbefree.wingman_app.MainActivity',manifest)
if __name__=='__main__':unittest.main()
