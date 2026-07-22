import 'package:flutter/material.dart';

import '../../core/signer_vault.dart';

class SignerOnboardingScreen extends StatefulWidget {
  const SignerOnboardingScreen({
    required this.vault,
    required this.record,
    required this.onUnlocked,
    super.key,
  });

  final SignerVault vault;
  final SignerVaultRecord? record;
  final ValueChanged<SignerVaultUnlock> onUnlocked;

  @override
  State<SignerOnboardingScreen> createState() => _SignerOnboardingScreenState();
}

class _SignerOnboardingScreenState extends State<SignerOnboardingScreen> {
  final TextEditingController _nsecController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  bool _busy = false;
  bool _obscureNsec = true;
  bool _obscurePin = true;
  String? _message;
  SignerVaultRecord? _record;

  bool get _hasVault => _record != null;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
  }

  @override
  void dispose() {
    _nsecController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  _hasVault ? 'Unlock Wingman' : 'Set Up Wingman Signer',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  _hasVault
                      ? 'Enter your PIN to unlock the local signer for this session.'
                      : 'Paste the nsec you want this app to sign with, then choose a local PIN.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                if (_hasVault) ...[
                  _IdentitySummary(record: _record!),
                  const SizedBox(height: 18),
                ] else ...[
                  TextField(
                    controller: _nsecController,
                    obscureText: _obscureNsec,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Nostr private key',
                      hintText: 'nsec1...',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        tooltip: _obscureNsec ? 'Show key' : 'Hide key',
                        onPressed: () {
                          setState(() {
                            _obscureNsec = !_obscureNsec;
                          });
                        },
                        icon: Icon(
                          _obscureNsec
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _pinController,
                  obscureText: _obscurePin,
                  keyboardType: TextInputType.number,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'PIN',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    suffixIcon: IconButton(
                      tooltip: _obscurePin ? 'Show PIN' : 'Hide PIN',
                      onPressed: () {
                        setState(() {
                          _obscurePin = !_obscurePin;
                        });
                      },
                      icon: Icon(
                        _obscurePin
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (!_hasVault) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmPinController,
                    obscureText: _obscurePin,
                    keyboardType: TextInputType.number,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Confirm PIN',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: Icon(
                    _hasVault
                        ? Icons.lock_open_outlined
                        : Icons.enhanced_encryption_outlined,
                  ),
                  label: Text(_hasVault ? 'Unlock' : 'Encrypt and Continue'),
                ),
                if (_hasVault) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _busy ? null : _resetVault,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Reset local signer vault'),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(_message!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (!_hasVault && pin != _confirmPinController.text.trim()) {
      setState(() {
        _message = 'PIN entries do not match.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = _hasVault ? 'Unlocking signer...' : 'Encrypting signer...';
    });
    try {
      final unlocked = _hasVault
          ? await widget.vault.unlock(pin: pin)
          : await widget.vault.create(
              nsec: _nsecController.text.trim(),
              pin: pin,
            );
      _nsecController.clear();
      _pinController.clear();
      _confirmPinController.clear();
      if (!mounted) return;
      widget.onUnlocked(unlocked);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _resetVault() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reset signer vault?'),
            content: const Text(
              'This removes the encrypted local signer. You will need to paste the nsec again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Reset'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await widget.vault.clear();
    if (!mounted) return;
    setState(() {
      _record = null;
      _message = 'Vault reset. Paste an nsec to continue.';
    });
  }
}

class _IdentitySummary extends StatelessWidget {
  const _IdentitySummary({required this.record});

  final SignerVaultRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.fingerprint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.npub,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Encrypted locally ${_dateLabel(record.createdAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
