import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  bool get unauthorized => status == 401;
  @override
  String toString() => message;
}

/// HTTP side of the hyprhand API for one rig.
class HyprClient {
  HyprClient(this.base, {this.token, this.onUnauthorized});

  final Uri base;
  String? token;
  void Function()? onUnauthorized;

  static const _cookie = 'hyprhand_session';
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 20);

  /// The server marks its cookie `Secure`, so it is carried by hand to keep
  /// plain-HTTP LAN rigs working.
  Map<String, String> get authHeaders =>
      token == null ? const {} : {'Cookie': '$_cookie=$token'};

  Uri url(String path, [Map<String, String>? q]) =>
      base.replace(path: path, queryParameters: q);

  Uri wsUrl(String path) =>
      url(path).replace(scheme: base.scheme == 'https' ? 'wss' : 'ws');

  Future<(HttpClientResponse, Uint8List)> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? json,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    HttpClientRequest? req;
    try {
      return await () async {
        req = await _http.openUrl(method, url(path, query));
        authHeaders.forEach(req!.headers.set);
        req!.followRedirects = false;
        if (method != 'GET') {
          final body = utf8.encode(jsonEncode(json ?? const {}));
          req!.headers.contentType = ContentType.json;
          req!.contentLength = body.length;
          req!.add(body);
        }
        final res = await req!.close();
        return (res, await _collect(res));
      }().timeout(timeout);
    } on TimeoutException {
      req?.abort();
      throw const ApiException('Rig took too long to answer');
    } on ApiException {
      rethrow;
    } on HandshakeException {
      throw const ApiException('TLS handshake failed');
    } on IOException {
      throw const ApiException('Rig unreachable');
    }
  }

  Future<Uint8List> _collect(Stream<List<int>> s) async {
    final b = BytesBuilder(copy: false);
    await for (final c in s) {
      b.add(c);
    }
    return b.takeBytes();
  }

  void _check(HttpClientResponse r, Uint8List body, String path) {
    if (r.statusCode == 401) {
      onUnauthorized?.call();
      throw const ApiException('Session expired', 401);
    }
    if (r.statusCode == 404) {
      throw ApiException('This server has no working $path', 404);
    }
    if (r.statusCode >= 400) {
      final text = utf8.decode(body, allowMalformed: true).trim();
      throw ApiException(
        text.isEmpty ? 'HTTP ${r.statusCode}' : text,
        r.statusCode,
      );
    }
  }

  Object? _decode(Uint8List body) {
    try {
      return jsonDecode(utf8.decode(body, allowMalformed: true));
    } on FormatException {
      throw const ApiException('Unexpected reply — is this a hyprhand server?');
    }
  }

  Future<Object?> getJson(
    String path, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final (r, b) = await _send('GET', path, timeout: timeout);
    _check(r, b, path);
    return _decode(b);
  }

  /// POST/PUT returning the reply; throws when the rig answers `ok: false`.
  Future<Json> call(
    String path, [
    Object? body,
    String method = 'POST',
    Duration timeout = const Duration(seconds: 12),
  ]) async {
    final (r, b) = await _send(method, path, json: body, timeout: timeout);
    _check(r, b, path);
    return okOrThrow(_decode(b));
  }

  static Json okOrThrow(Object? v) {
    final j = v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    if (j['ok'] != true) {
      throw ApiException(
        '${j['error'] ?? j['detail'] ?? 'The rig refused that'}',
      );
    }
    return j;
  }

  Future<Uint8List> getBytes(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final (r, b) = await _send('GET', path, query: query, timeout: timeout);
    _check(r, b, path);
    return b;
  }

  // ── auth ──

  /// Returns the session token.
  Future<String> login(String pin) async {
    final (r, b) = await _send('POST', '/login', json: {'pin': pin});
    if (r.statusCode == 200) {
      for (final c in r.cookies) {
        if (c.name == _cookie) return token = c.value;
      }
      throw const ApiException('Server sent no session');
    }
    Object? j;
    try {
      j = jsonDecode(utf8.decode(b, allowMalformed: true));
    } on FormatException {
      j = null;
    }
    final err = j is Map ? j['error'] : null;
    throw ApiException(
      '${err ?? 'Login failed (HTTP ${r.statusCode})'}',
      r.statusCode,
    );
  }

  /// true/false for a definite answer, null when the rig can't be reached.
  Future<bool?> sessionValid() async {
    try {
      final (r, _) = await _send(
        'GET',
        '/input/available',
        timeout: const Duration(seconds: 6),
      );
      if (r.statusCode == 401) return false;
      return r.statusCode == 200 ? true : null;
    } on ApiException {
      return null;
    }
  }

  Future<bool> inputAvailable() async {
    final j = await getJson('/input/available');
    return j is Map && j['ok'] == true;
  }

  Future<String> themeCss() async =>
      utf8.decode(await getBytes('/theme.css'), allowMalformed: true);

  // ── files ──

  /// Streams a file as multipart. Verifies the byte count the server reports:
  /// stock servers cap bodies at 2 MB and store an empty file with `ok: true`.
  Future<Json> upload(
    File file,
    String name, {
    String path = '/upload',
    String field = 'file',
    void Function(double)? onProgress,
  }) async {
    final size = await file.length();
    final boundary = 'hyprhand-${DateTime.now().microsecondsSinceEpoch}';
    final safe = name.replaceAll(RegExp(r'["\r\n\\/]'), '_');
    final head = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="$field"; filename="$safe"\r\n'
      'Content-Type: application/octet-stream\r\n\r\n',
    );
    final tail = utf8.encode('\r\n--$boundary--\r\n');
    try {
      final req = await _http.postUrl(url(path));
      authHeaders.forEach(req.headers.set);
      req.headers.set(
        'Content-Type',
        'multipart/form-data; boundary=$boundary',
      );
      req.contentLength = head.length + size + tail.length;
      req.add(head);
      var sent = 0;
      await req.addStream(
        file.openRead().map((c) {
          sent += c.length;
          onProgress?.call(size == 0 ? 1 : sent / size);
          return c;
        }),
      );
      req.add(tail);
      final res = await req.close().timeout(const Duration(minutes: 2));
      final body = await _collect(res);
      _check(res, body, path);
      final j = okOrThrow(_decode(body));
      final got = j['size'];
      if (got is num && got.toInt() != size) {
        throw ApiException(
          size > 2000000
              ? 'Server stored ${got.toInt()} of $size bytes — it limits uploads to 2 MB'
              : 'Upload incomplete: ${got.toInt()} of $size bytes',
        );
      }
      return j;
    } on TimeoutException {
      throw const ApiException('Upload timed out');
    } on IOException {
      throw ApiException(
        size > 2000000
            ? 'Server closed the upload — it limits bodies to 2 MB'
            : 'Connection lost while uploading',
      );
    }
  }

  /// Share text/URL: the rig opens links and copies anything else.
  Future<String> shareText(String text) async {
    final boundary = 'hyprhand-${DateTime.now().microsecondsSinceEpoch}';
    final body = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="text"\r\n\r\n'
      '$text\r\n--$boundary--\r\n',
    );
    try {
      final req = await _http.postUrl(url('/share/api'));
      authHeaders.forEach(req.headers.set);
      req.headers.set(
        'Content-Type',
        'multipart/form-data; boundary=$boundary',
      );
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 15));
      final b = await _collect(res);
      _check(res, b, '/share/api');
      return '${okOrThrow(_decode(b))['detail']}';
    } on TimeoutException {
      throw const ApiException('Rig took too long to answer');
    } on IOException {
      throw const ApiException('Rig unreachable');
    }
  }

  void close() => _http.close(force: true);
}
