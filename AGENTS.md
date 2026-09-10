# Repository guidance

Store operational agent handoffs, worker briefs, installation results, screenshots,
and run-specific validation evidence only under ignored `tmp/docs/handoffs/`.
Do not create tracked handoff directories elsewhere or force-add ignored files.
Legacy `docs/handoffs/` and handoff filenames under `docs/` are ignored to prevent
accidental reintroduction.

Keep general product documentation, reusable validation procedures, and code in
Git. Use generic device labels and placeholders; never copy personal device names,
serial numbers, UDIDs, or device UUIDs into tracked files, commit messages, or
task reports. Public docs should describe procedures without linking private
local evidence files.

Preserve existing local records byte-for-byte when moving them. If a destination
exists with different content, retain both under distinct names and verify hashes.
Keep privacy audits, replacement data, and history backups ignored and private.
Ordinary deletion does not purge Git history. Prepare history rewrites in an
isolated local mirror and obtain explicit authorization before changing shared
history or deleting remote refs.
