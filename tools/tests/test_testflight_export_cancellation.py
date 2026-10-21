"""Cancellation is scoped to proved, finished, never-uploaded exports."""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'ios'))
import testflight_export_cancellation as c
import testflight_release as r
import testflight_export_recovery as recovery
import nightly_testflight as nightly
from appstore_connect import APP


class CancellationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.run = self.root / 'original'; self.run.mkdir()
        self.logs = self.run / 'native.xcdistributionlogs'; self.logs.mkdir()
        (self.logs / 'ContentDelivery.log').write_text('retained native creation proof')
        self.s = {'export_started_ns': 1704067199 * 10**9, 'source': {'wmapp': 'a'*40, 'flightdeck': 'b'*40}}
        r.write(self.run / 'state.json', self.s)
        self.entry = dict(repository=str(self.root), run_path=str(self.run), export_logs=str(self.logs),
                          owner='prior', day='2024-01-01', source_commit='a'*40,
                          state_sha256=r.digest(self.run / 'state.json'), upload_id='reservation-1',
                          version='0.1.7', build=16, created_at='2024-01-01T00:00:00Z')
        self.proof = {'upload_id': 'reservation-1', 'logs': str(self.logs)}
        self.claim = dict(owner='prior', source=self.s['source'], status='failed', finished_at='finished')
        self.h = {'pending_upload_ids': ['reservation-1'], 'pending_build_ids': [], 'builds': [],
                  'uploads': [{'id': 'reservation-1', 'attributes': dict(platform='IOS', cfBundleVersion='16',
                    cfBundleShortVersionString='0.1.7', createdDate=self.entry['created_at'], uploadedDate=None,
                    state=dict(state='AWAITING_UPLOAD', errors=[], warnings=[], infos=[]))}]}
        self.client = Mock(); self.client.preflight.return_value = self.h; self.client.all.return_value = []
        self.reference = self.root / 'reference.json'; r.write(self.reference, {'schema': 1, 'existing': 'preserved'})
        self.manifest = self.root / 'manifest.json'
        r.write(self.manifest, dict(schema=1, app_id=APP, reviewed_by='coordinator',
                                  authorization='Explicit reviewed cancellation', entries=[self.entry]))
        self.args = SimpleNamespace(confirm_cancel_exports=True, cancellation_manifest=self.manifest,
                                    auth_reference=self.reference)

    def invoke(self, output='cancelled'):
        with patch.object(nightly, 'safe_private'), patch.object(c, 'local_proof',
                return_value=(self.s, self.proof, self.claim)), patch.object(c, 'claim_fact'), \
                patch.object(recovery, 'stopped_session', return_value={'id': 'prior', 'archived_at': 'stopped'}), \
                patch.dict(os.environ, {'SESSION_ID': 'coordinator'}):
            return c.cancel(r, self.client, self.args, self.root / output)

    def test_reviewed_cancellation_preserves_states_reference_and_apple_records(self):
        state_before = (self.run / 'state.json').read_bytes(); ref_before = self.reference.read_bytes()
        self.invoke()
        self.assertEqual((self.run / 'state.json').read_bytes(), state_before)
        self.assertEqual((self.root / 'cancelled/auth-reference-before.json').read_bytes(), ref_before)
        config = r.read(self.reference)
        self.assertEqual(config['existing'], 'preserved')
        self.assertEqual(set(config['cancelled_export_uploads']), {'reservation-1'})
        self.client.request.assert_not_called()
        self.assertEqual(self.h['pending_upload_ids'], ['reservation-1'])
        with self.assertRaises(ValueError): self.invoke()

    def test_unmatched_pending_processing_or_delivery_never_changes_reference(self):
        for mutate in [lambda h: h['pending_upload_ids'].append('unknown'),
                       lambda h: h['pending_build_ids'].append('processing'),
                       lambda h: h['builds'].append({'attributes': {'version': '16'}}),
                       lambda h: h['uploads'][0]['attributes'].update(uploadedDate='now'),
                       lambda h: h['uploads'][0]['attributes'].update(createdDate='2023-01-01T00:00:00Z'),
                       lambda h: h['uploads'][0]['attributes']['state'].update(state='PROCESSING')]:
            h = copy.deepcopy(self.h); mutate(h); self.client.preflight.return_value = h
            before = self.reference.read_bytes()
            with self.assertRaises(ValueError): self.invoke()
            self.assertEqual(self.reference.read_bytes(), before)
            self.assertFalse((self.root / 'cancelled').exists())
        self.client.preflight.return_value = self.h; self.client.all.return_value = [{'id': 'file'}]
        with self.assertRaises(ValueError): self.invoke()

    def test_review_and_confirmation_are_required(self):
        self.args.confirm_cancel_exports = False
        with self.assertRaises(ValueError): self.invoke()
        self.args.confirm_cancel_exports = True
        manifest = r.read(self.manifest); manifest['reviewed_by'] = 'another'; r.write(self.manifest, manifest)
        with self.assertRaises(ValueError): self.invoke()

    def test_live_other_owner_or_active_claim_blocks(self):
        with patch.object(nightly, 'safe_private'), patch.object(c, 'local_proof', return_value=(self.s, self.proof, self.claim)), \
                patch.object(c, 'claim_fact', side_effect=ValueError('active claim')), \
                patch.dict(os.environ, {'SESSION_ID':'coordinator'}):
            with self.assertRaises(ValueError): c.cancel(r, self.client, self.args, self.root / 'cancelled')
        with patch.object(nightly, 'safe_private'), patch.object(c, 'local_proof', return_value=(self.s, self.proof, self.claim)), \
                patch.object(c, 'claim_fact'), patch.object(recovery, 'stopped_session', side_effect=ValueError('live')), \
                patch.dict(os.environ, {'SESSION_ID':'coordinator'}):
            with self.assertRaises(ValueError): c.cancel(r, self.client, self.args, self.root / 'cancelled')

    def test_history_revalidates_exact_proof_and_rejects_drift(self):
        self.invoke(); config=r.read(self.reference); rule=config['cancelled_export_uploads']['reservation-1']
        entry=r.read(self.root / 'cancelled/cancellation.json')['entries'][0]
        attrs=self.h['uploads'][0]['attributes']
        with patch.object(nightly,'safe_private'), patch.object(c,'local_proof',return_value=(self.s,self.proof,self.claim)):
            self.assertTrue(c.verified_rule(self.client,'reservation-1',attrs,rule))
            for change in ({'cfBundleVersion':'17'}, {'uploadedDate':'now'}):
                with self.assertRaises(ValueError): c.verified_rule(self.client,'reservation-1',dict(attrs,**change),rule)
            with patch.object(c,'local_proof',return_value=(self.s,dict(self.proof,logs='changed'),self.claim)):
                with self.assertRaises(ValueError): c.verified_rule(self.client,'reservation-1',attrs,rule)
        (self.root / 'cancelled/cancellation.json').write_text('{}')
        with patch.object(nightly,'safe_private'):
            with self.assertRaises(ValueError): c.verified_rule(self.client,'reservation-1',attrs,rule)

    def test_claim_must_match_source_and_be_finished_not_active(self):
        ledger=dict(schema=2,days={'2024-01-01':{'attempts':[self.claim]}})
        p=self.root/'tmp/docs/handoffs/nightly-testflight';p.mkdir(parents=True);r.write(p/'ledger.json',ledger)
        with patch.object(c,'private_repo_path'):
            self.assertEqual(c.claim_fact(self.root,'prior','2024-01-01',self.s['source']),self.claim)
            with self.assertRaises(ValueError): c.claim_fact(self.root,'wrong','2024-01-01',self.s['source'])
            ledger['days']['2024-01-01']['attempts'][0]['status']='active';r.write(p/'ledger.json',ledger)
            with self.assertRaises(ValueError): c.claim_fact(self.root,'prior','2024-01-01',self.s['source'],require_idle=True)

    def test_private_boundary_rejects_symlink_and_outside_run(self):
        with self.assertRaises(ValueError): c.private_repo_path(self.root,self.root/'outside')
        p=self.root/'tmp/docs/handoffs';p.mkdir(parents=True)
        link=p/'link';link.symlink_to(self.run,target_is_directory=True)
        with self.assertRaises(ValueError): c.private_repo_path(self.root,link/'state.json')


if __name__ == '__main__':
    unittest.main()
