import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import 'nstack_access.dart';
import 'nstack_discovery.dart';
import 'nstack_models.dart';
import 'nstack_recovery.dart';
import 'nstack_store.dart';

class NStackScreen extends StatefulWidget {
  const NStackScreen({
    required this.config,
    required this.registryStore,
    required this.grantStore,
    required this.accessService,
    required this.discoveryService,
    required this.recoveryService,
    required this.onRegistryChanged,
    super.key,
  });

  final AppConfig config;
  final NStackRegistryStore registryStore;
  final NStackGrantStore grantStore;
  final NStackAccessService accessService;
  final NStackWorkspaceDiscoveryService discoveryService;
  final NStackRecoveryService recoveryService;
  final VoidCallback onRegistryChanged;

  @override
  State<NStackScreen> createState() => _NStackScreenState();
}

class _NStackScreenState extends State<NStackScreen> {
  NStackRegistry _registry = const NStackRegistry();
  List<NStackDiscoveryGrant> _grants = const [];
  Map<String, dynamic>? _status;
  bool _busy = false;
  String? _refreshingStackId;
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.accessService.addListener(_refreshView);
    widget.grantStore.addListener(_refreshView);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant NStackScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accessService != widget.accessService) {
      oldWidget.accessService.removeListener(_refreshView);
      widget.accessService.addListener(_refreshView);
    }
    if (oldWidget.grantStore != widget.grantStore) {
      oldWidget.grantStore.removeListener(_refreshView);
      widget.grantStore.addListener(_refreshView);
    }
    if (oldWidget.config.deviceNpub != widget.config.deviceNpub) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.accessService.removeListener(_refreshView);
    widget.grantStore.removeListener(_refreshView);
    super.dispose();
  }

  void _refreshView() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final identity = widget.config.deviceNpub;
    final registry = await widget.registryStore.load(identity);
    final grants = await widget.grantStore.list(identity);
    final status = await widget.recoveryService.statusStore.load(identity);
    if (!mounted || identity != widget.config.deviceNpub) return;
    setState(() {
      _registry = registry;
      _grants = grants;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('NStacks',
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
            FilledButton.icon(
              key: const ValueKey('add-nstack'),
              onPressed: _busy || widget.config.deviceNpub.isEmpty
                  ? null
                  : () => _editStack(),
              icon: const Icon(Icons.add),
              label: const Text('Add NStack'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose the NStacks this identity uses. Websites see nothing beyond '
          'the window.NStack version until you approve discovery.',
        ),
        const SizedBox(height: 18),
        if (_registry.stacks.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.dns_outlined),
              title: Text('No NStacks yet'),
              subtitle:
                  Text('Add one to enable discovery and encrypted backup.'),
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        for (final stack in _registry.stacks) _stackCard(stack),
        const SizedBox(height: 18),
        _recoveryCard(),
        const SizedBox(height: 18),
        _accessCard(),
        if (_message != null) ...[
          const SizedBox(height: 14),
          Text(_message!, key: const ValueKey('nstack-message')),
        ],
      ],
    );
  }

  Widget _stackCard(NStackEntry stack) {
    final active = _registry.activeStackId == stack.id;
    final host = _registry.hostStackId == stack.id;
    return Card(
      key: ValueKey('nstack-${stack.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              leading: Icon(host ? Icons.home_work : Icons.dns_outlined),
              title: Text(stack.name),
              subtitle:
                  Text('${stack.url}\n${stack.workspaces.length} workspace(s)'),
              isThreeLine: true,
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Refresh ${stack.name} workspaces',
                    onPressed: _busy ? null : () => _refreshStack(stack),
                    icon: _refreshingStackId == stack.id
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Change ${stack.name} address',
                    onPressed: _busy ? null : () => _editStack(stack),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Remove ${stack.name}',
                    onPressed: _busy ? null : () => _removeStack(stack),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            if (stack.workspaceDiscovery == null)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Authenticated refresh required'),
                subtitle: Text(
                    'Previously entered workspace rows are retained until refresh replaces them with server discovery.'),
              )
            else if (stack.workspaceDiscovery!.hasError)
              ListTile(
                leading: const Icon(Icons.warning_amber),
                title: const Text('Workspace refresh failed'),
                subtitle: Text(
                  '${stack.workspaceDiscovery!.errorMessage}\n'
                  '${stack.workspaces.isEmpty ? 'No workspace was saved.' : 'Showing last-known-good workspaces; they may be stale.'}',
                ),
              )
            else if (stack.workspaces.isEmpty)
              const ListTile(
                leading: Icon(Icons.workspaces_outline),
                title: Text('No accessible workspaces'),
                subtitle: Text(
                    'The active identity authenticated successfully but this NStack returned no workspaces.'),
              )
            else
              for (final workspace in stack.workspaces)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.workspaces_outline),
                  title: Text(workspace.name),
                  subtitle: Text(workspace.remoteId),
                ),
            ListTile(
              leading: Icon(active
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              onTap: _busy
                  ? null
                  : () async {
                      await widget.registryStore
                          .selectActive(widget.config.deviceNpub, stack.id);
                      widget.onRegistryChanged();
                      await _load();
                    },
              title: const Text('Use browser links and preferences'),
            ),
            CheckboxListTile(
              value: host,
              onChanged: _busy
                  ? null
                  : (value) async {
                      await widget.registryStore.selectHost(
                        widget.config.deviceNpub,
                        value == true ? stack.id : null,
                      );
                      await _load();
                    },
              title: const Text('Host encrypted NBrowser backup'),
            ),
            if (active)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Text(
                      '${stack.settings.bookmarks.length} browser link(s) stored for this NStack.'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _recoveryCard() {
    final published = _status?['last_published_at']?.toString();
    final restored = _status?['last_restored_at']?.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Encrypted backup and recovery',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'The host stores only NIP-44 ciphertext. A signed, self-encrypted '
              'Nostr hint points to the exact object and hash.',
            ),
            if (published != null) Text('Last published: $published'),
            if (restored != null) Text('Last restored: $restored'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const ValueKey('publish-nstack-backup'),
                  onPressed: _busy ||
                          !widget.config.hasDeviceSecret ||
                          _registry.hostStack == null
                      ? null
                      : _publish,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Publish backup'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('recover-nstack-backup'),
                  onPressed:
                      _busy || !widget.config.hasDeviceSecret ? null : _recover,
                  icon: const Icon(Icons.restore),
                  label: const Text('Find recovery'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _accessCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Website access',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_grants.isEmpty)
              const Text('No websites can discover saved connections.'),
            for (final grant in _grants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.travel_explore),
                title: Text(grant.origin),
                subtitle: Text('${grant.stackIds.length} disclosed NStack(s)'),
                trailing: TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await widget.accessService.revokeOrigin(
                              widget.config.deviceNpub, grant.origin);
                          await _load();
                        },
                  child: const Text('Revoke'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editStack([NStackEntry? existing]) async {
    final address = await showDialog<String>(
      context: context,
      builder: (context) => _NStackEditor(existingAddress: existing?.url),
    );
    if (address == null) return;
    await _run(() async {
      _message = 'Authenticating and discovering workspaces…';
      if (mounted) setState(() {});
      final result = existing == null
          ? await widget.discoveryService.add(
              identityNpub: widget.config.deviceNpub,
              secret: widget.config.deviceSecret,
              address: address,
            )
          : await widget.discoveryService.changeAddress(
              identityNpub: widget.config.deviceNpub,
              secret: widget.config.deviceSecret,
              stackId: existing.id,
              address: address,
            );
      widget.onRegistryChanged();
      _message = result.workspaces.isEmpty
          ? '${result.name} saved; this identity has no accessible workspaces.'
          : '${result.name} saved with ${result.workspaces.length} workspace(s).';
    });
  }

  Future<void> _refreshStack(NStackEntry stack) async {
    setState(() => _refreshingStackId = stack.id);
    await _run(() async {
      final refreshed = await widget.discoveryService.refresh(
        identityNpub: widget.config.deviceNpub,
        secret: widget.config.deviceSecret,
        stackId: stack.id,
      );
      widget.onRegistryChanged();
      _message = refreshed.workspaces.isEmpty
          ? 'Refresh complete; no accessible workspaces were returned.'
          : 'Refreshed ${refreshed.workspaces.length} workspace(s).';
    });
    if (mounted) setState(() => _refreshingStackId = null);
  }

  Future<void> _removeStack(NStackEntry stack) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Remove ${stack.name}?'),
            content: const Text(
                'This removes its local metadata and website discovery aliases. Existing encrypted backup objects are immutable.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Remove')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _run(() async {
      widget.accessService.revokeStack(stack.id);
      await widget.registryStore.remove(widget.config.deviceNpub, stack.id);
      widget.onRegistryChanged();
      _message = '${stack.name} removed.';
    });
  }

  Future<void> _publish() => _run(() async {
        final result = await widget.recoveryService.publish(
          identityNpub: widget.config.deviceNpub,
          publicKeyHex: widget.config.devicePublicKeyHex,
          secret: widget.config.deviceSecret,
        );
        _message = result.published
            ? 'Backup published to ${result.acceptedRelays.length}/${result.totalRelays} relays.'
            : 'Encrypted object uploaded, but no relay accepted the recovery hint.';
      });

  Future<void> _recover() => _run(() async {
        final preview = await widget.recoveryService.retrieve(
          identityNpub: widget.config.deviceNpub,
          publicKeyHex: widget.config.devicePublicKeyHex,
          secret: widget.config.deviceSecret,
        );
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Restore NBrowser settings?'),
                content: Text(
                  'Host: ${preview.pointer.hostUrl}\n'
                  'Snapshot: ${preview.snapshot.createdAt.toLocal()}\n'
                  'NStacks: ${preview.snapshot.registry.stacks.length}\n'
                  'Browser links: ${preview.snapshot.registry.stacks.fold<int>(0, (sum, stack) => sum + stack.settings.bookmarks.length)}\n\n'
                  'The current local registry changes only after you confirm.',
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Restore')),
                ],
              ),
            ) ??
            false;
        if (!confirmed) {
          _message = 'Recovery preview checked; nothing was changed.';
          return;
        }
        await widget.recoveryService
            .restoreConfirmed(widget.config.deviceNpub, preview);
        widget.onRegistryChanged();
        _message = 'NStacks and browser links restored.';
      });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      _message = error.toString().replaceFirst('Bad state: ', '');
    } finally {
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _NStackEditor extends StatefulWidget {
  const _NStackEditor({this.existingAddress});
  final String? existingAddress;

  @override
  State<_NStackEditor> createState() => _NStackEditorState();
}

class _NStackEditorState extends State<_NStackEditor> {
  late final TextEditingController _url;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.existingAddress ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingAddress == null
          ? 'Add NStack'
          : 'Change NStack address'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _url,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'NStack HTTPS address',
                    helperText:
                        'NBrowser will authenticate and discover every workspace available to the active identity.',
                  )),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    final url = canonicalNStackUrl(_url.text);
    if (url == null) {
      setState(() => _error = 'Enter a valid HTTPS NStack address.');
      return;
    }
    Navigator.pop(context, url);
  }
}
