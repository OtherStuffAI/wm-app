"""Reviewed local cancellation of proved never-uploaded native exports.

Apple records and original run states are preserved. This is not an Apple delete
or an inference from empty files: native creation proof, validated signed bytes,
finished claims and stopped owners must all agree before a scoped rule is saved.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess

from appstore_connect import APP, owner_file, require


def private_repo_path(root, path):
    root, path = Path(root).absolute(), Path(path).absolute()
    require(not any(p.is_symlink() for p in [path, *path.parents]), 'Cancellation evidence cannot traverse symlinks.')
    require(path.is_relative_to(root / 'tmp/docs/handoffs'), 'Run evidence must remain in its repository private handoffs.')
    top = subprocess.check_output(['git', '-C', str(root), 'rev-parse', '--show-toplevel'], text=True).strip()
    require(top == str(root), 'Expected an exact repository root.')
    relative = str(path.relative_to(root))
    subprocess.run(['git', '-C', str(root), 'check-ignore', '-q', relative], check=True)
    require(not subprocess.check_output(['git', '-C', str(root), 'ls-files', '--', relative]), 'Cancellation evidence is tracked.')


def claim_fact(root, owner, day, source, require_idle=False):
    from nightly_testflight import _ledger, active_claim
    path = Path(root) / 'tmp/docs/handoffs/nightly-testflight/ledger.json'
    private_repo_path(root, path)
    ledger = _ledger(json.loads(owner_file(path).read_text()))
    if require_idle:
        require(active_claim(ledger) is None, 'Active release claim blocks export cancellation.')
    entries = [e for e in ledger.get('days', {}).get(day, {}).get('attempts', [])
               if e.get('owner') == owner and e.get('source') == source]
    require(len(entries) == 1 and entries[0].get('status') == 'failed' and entries[0].get('finished_at'),
            'Cancellation requires the exact finished failed source claim.')
    return entries[0]


def local_proof(r, entry):
    from testflight_export_recovery import export_proof
    root, run, logs = (Path(entry[k]).absolute() for k in ('repository', 'run_path', 'export_logs'))
    require(run.parent == root / 'tmp/docs/handoffs/testflight', 'Expected a retained release run.')
    for path in (run, logs, run / 'state.json'):
        private_repo_path(root, path)
    require(logs.parent == run, 'Native logs must be retained inside their original run.')
    state_path = run / 'state.json'
    require(r.digest(state_path) == entry['state_sha256'], 'Cancelled export state changed.')
    s = json.loads(owner_file(state_path).read_text())
    require(s.get('source_commit') == entry['source_commit'] and s.get('version') == entry['version'] and
            s.get('build') == entry['build'] and s.get('audience') == 'internal', 'Cancelled source/version/audience mismatch.')
    policy = Path(entry['export_policy']).absolute()
    require(policy.is_relative_to(run), 'Retained export policy must be inside the original run.')
    private_repo_path(root, policy)
    proof = export_proof(r, run, s, logs, policy_path=policy,
                         private_check=lambda p: private_repo_path(root, p))
    require(proof['upload_id'] == entry['upload_id'], 'Cancellation targets another native reservation.')
    claim = claim_fact(root, entry['owner'], entry['day'], s['source'])
    return s, proof, claim


def reservation(client, h, entry, proof):
    matches = [u for u in h['uploads'] if u['id'] == entry['upload_id']]
    require(len(matches) == 1, 'Cancelled reservation absent or ambiguous.')
    a = matches[0]['attributes']
    require(a['platform'] == 'IOS' and a['cfBundleVersion'] == str(entry['build']) and
            a['cfBundleShortVersionString'] == entry['version'] and a['createdDate'] == entry['created_at'] and
            a['uploadedDate'] is None and a['state'] ==
            {'state': 'AWAITING_UPLOAD', 'errors': [], 'warnings': [], 'infos': []},
            'Cancelled reservation acquired delivery evidence or changed identity.')
    import datetime as dt
    created = dt.datetime.fromisoformat(a['createdDate'].replace('Z', '+00:00'))
    state = json.loads(owner_file(Path(entry['run_path']) / 'state.json').read_text())
    require(created.tzinfo is not None and state['export_started_ns'] / 1e9 <= created.timestamp() <=
            (Path(proof['logs']) / 'ContentDelivery.log').stat().st_mtime, 'Native reservation creation time mismatch.')
    require(not client.all(f'/v1/buildUploads/{entry["upload_id"]}/buildUploadFiles?limit=200'),
            'Cancelled reservation has upload files; delivery requires reconciliation.')
    require(not any(int(b['attributes']['version']) == entry['build'] for b in h['builds']),
            'A processed/processing build already exists for the cancelled number.')


def verified_rule(client, ident, attributes, rule):
    """Recheck every cancelled reservation on every full Apple history read."""
    import testflight_release as r
    from nightly_testflight import safe_private
    path = Path(rule['evidence_path']); safe_private(path)
    raw = owner_file(path).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == rule['evidence_sha256'], 'Cancellation evidence changed.')
    evidence = json.loads(raw)
    require(evidence.get('schema') == 1 and evidence.get('app_id') == APP and
            evidence.get('basis') == 'reviewed_cancelled_native_exports', 'Invalid cancellation evidence.')
    matches = [e for e in evidence['entries'] if e['upload_id'] == ident]
    require(len(matches) == 1, 'Cancellation rule has no exact evidence entry.')
    entry = matches[0]
    require(all(rule[k] == entry[k] for k in ('version', 'build', 'created_at')), 'Cancellation rule drift.')
    state, proof, claim = local_proof(r, entry)
    require(proof == entry['native_proof'] and claim == entry['finished_claim'], 'Cancellation proof or claim changed.')
    reservation(client, {'uploads': [{'id': ident, 'attributes': attributes}], 'builds': []}, entry, proof)
    return True


def cancel(r, client, a, output):
    from nightly_testflight import safe_private
    from testflight_export_recovery import stopped_session
    require(a.confirm_cancel_exports and a.cancellation_manifest, 'Explicit reviewed export cancellation is required.')
    require(not output.exists(), 'Cancellation record exists; inspect it, never overwrite.')
    manifest_path = Path(a.cancellation_manifest).absolute(); safe_private(manifest_path)
    manifest = json.loads(owner_file(manifest_path).read_text())
    owner = os.environ.get('SESSION_ID')
    require(owner and manifest.get('reviewed_by') == owner and manifest.get('schema') == 1 and
            manifest.get('app_id') == APP and bool(manifest.get('authorization')), 'Missing scoped cancellation review.')
    entries = manifest.get('entries', [])
    require(1 <= len(entries) <= 8 and len({e['upload_id'] for e in entries}) == len(entries) and
            len({e['run_path'] for e in entries}) == len(entries), 'Invalid/duplicate cancellation set.')
    proved = []
    for entry in entries:
        s, proof, claim = local_proof(r, entry)
        claim_fact(entry['repository'], entry['owner'], entry['day'], s['source'], require_idle=True)
        stopped = ({'id': owner, 'current_coordinator': True} if entry['owner'] == owner else
                   stopped_session(entry['owner'], source_repo=entry['repository']))
        proved.append(dict(entry, native_proof=proof, finished_claim=claim, stopped_owner=stopped))
    h = client.preflight()
    require(set(h['pending_upload_ids']) == {e['upload_id'] for e in entries} and not h['pending_build_ids'],
            'Unmatched Apple pending delivery blocks cancellation.')
    for entry in proved:
        reservation(client, h, entry, entry['native_proof'])
    # No Apple mutations. Save immutable proof before the atomic reference update.
    output.mkdir(mode=0o700)
    r.write(output / 'manifest.json', manifest)
    r.write(output / 'apple-before.json', h)
    r.write(output / 'cancellation.json', dict(schema=1, app_id=APP,
        basis='reviewed_cancelled_native_exports', reviewed_by=owner, authorization=manifest['authorization'],
        observed_at=r.now(), entries=proved))
    reference = Path(a.auth_reference)
    before = owner_file(reference).read_bytes()
    backup = output / 'auth-reference-before.json'; backup.write_bytes(before); backup.chmod(0o600)
    require(backup.read_bytes() == before, 'Reference backup mismatch.')
    config = json.loads(before)
    rules = config.setdefault('cancelled_export_uploads', {})
    for entry in proved:
        require(entry['upload_id'] not in rules, 'Cancellation already configured.')
        rules[entry['upload_id']] = {k: entry[k] for k in ('version', 'build', 'created_at')}
        rules[entry['upload_id']].update(evidence_path=str((output / 'cancellation.json').absolute()),
                                       evidence_sha256=r.digest(output / 'cancellation.json'))
    require(owner_file(reference).read_bytes() == before, 'Credential reference changed during review.')
    r.write(reference, config)
    print(json.dumps({'cancelled_export_ids': [e['upload_id'] for e in proved],
                      'apple_records_preserved': True, 'original_states_preserved': True,
                      'upload_performed': False}, indent=2))
