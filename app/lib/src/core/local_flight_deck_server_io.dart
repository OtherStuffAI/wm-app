import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class LocalFlightDeckServer {
  LocalFlightDeckServer._(this._server, this._assetKeys) {
    _server.listen(_serve);
  }

  static const host = '127.0.0.1';
  static const port = 47831;
  static const origin = 'http://$host:$port';
  static const _assetPrefix = 'assets/flightdeck/';

  final HttpServer _server;
  final Set<String> _assetKeys;

  static Future<LocalFlightDeckServer> start() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetKeys = manifest
        .listAssets()
        .where((key) => key.startsWith(_assetPrefix))
        .toSet();
    if (!assetKeys.contains('${_assetPrefix}index.html')) {
      throw StateError('The packaged Flight Deck bundle is missing index.html');
    }
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: true,
    );
    return LocalFlightDeckServer._(server, assetKeys);
  }

  String get url => '$origin/';

  Future<void> _serve(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final relativePath =
        request.uri.path == '/' ? 'index.html' : request.uri.path.substring(1);
    var assetKey = '$_assetPrefix$relativePath';
    if (!_assetKeys.contains(assetKey) && !_hasFileExtension(relativePath)) {
      assetKey = '${_assetPrefix}index.html';
    }
    if (!_assetKeys.contains(assetKey)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      final data = await rootBundle.load(assetKey);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      request.response.headers
        ..contentType = _contentType(assetKey)
        ..set(HttpHeaders.cacheControlHeader, _cacheControl(assetKey))
        ..set('X-Content-Type-Options', 'nosniff');
      request.response.contentLength = bytes.length;
      if (request.method == 'GET') {
        request.response.add(Uint8List.fromList(bytes));
      }
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
    }
    await request.response.close();
  }

  static bool _hasFileExtension(String path) {
    final lastSegment = path.split('/').last;
    return lastSegment.contains('.');
  }

  static ContentType _contentType(String path) {
    final extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'html' => ContentType.html,
      'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'json' || 'webmanifest' => ContentType.json,
      'png' => ContentType('image', 'png'),
      'svg' => ContentType('image', 'svg+xml'),
      'ico' => ContentType('image', 'x-icon'),
      'txt' || 'md' => ContentType.text,
      'woff' => ContentType('font', 'woff'),
      'woff2' => ContentType('font', 'woff2'),
      _ => ContentType.binary,
    };
  }

  static String _cacheControl(String path) {
    if (path.contains('/assets/')) return 'public, max-age=31536000, immutable';
    return 'no-cache';
  }
}
