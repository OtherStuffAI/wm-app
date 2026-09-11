import 'dart:async';
import 'dart:io';

/// A bounded stream with cancellation retained through close, rename and export.
class DriveNativeSave {
  DriveNativeSave(this.partial, this.target) : sink = partial.openWrite();
  final File partial;
  final String target;
  final IOSink sink;
  bool cancelled = false;
  Future<void>? _closing;
  Future<void>? _finishing;
  Future<void> _close() => _closing ??= sink.close();

  Future<void> cancel() async {
    cancelled = true;
    if (_finishing != null) {
      try {
        await _finishing;
      } catch (_) {}
    } else {
      await _close();
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<void> finish(
      {required bool Function() revoked,
      Future<void> Function()? export,
      Future<void> Function()? beforeCommit}) {
    if (_finishing != null) throw StateError('save_finishing');
    return _finishing = _finish(revoked, export, beforeCommit);
  }

  Future<void> _finish(bool Function() revoked, Future<void> Function()? export,
      Future<void> Function()? beforeCommit) async {
    final destination = File(target);
    final backup = File('${partial.path}.previous');
    var backedUp = false, committed = false;
    void check() {
      if (cancelled || revoked()) throw StateError('cancelled');
    }

    try {
      await _close();
      if (beforeCommit != null) await beforeCommit();
      check();
      if (await destination.exists()) {
        check();
        await destination.rename(backup.path);
        backedUp = true;
      }
      check();
      await partial.rename(target);
      committed = true;
      check();
      if (export != null) await export();
      check();
    } catch (_) {
      if (committed && await destination.exists()) await destination.delete();
      if (backedUp) await backup.rename(target);
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
    if (backedUp) await backup.delete();
  }
}
