import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'exceptions.dart';
import 'models.dart';

/// A client for the Claris FileMaker Data API.
///
/// This package is not affiliated with or endorsed by Claris International Inc.
///
/// The client manages the session token transparently: the first call that
/// needs a token will log in, and the token is reused for subsequent calls.
/// If the host rejects the token (expiry / idle timeout), the client logs in
/// again once and retries.
///
/// ```dart
/// final fm = FileMakerClient(
///   host: 'https://fms.example.com',
///   database: 'Contacts',
///   username: 'admin',
///   password: 'secret',
/// );
///
/// final results = await fm.find(
///   layout: 'Contacts',
///   query: [{'name': 'John'}],
/// );
/// for (final r in results.records) {
///   print(r['name']);
/// }
/// await fm.logout();
/// ```
class FileMakerClient {
  /// Creates a [FileMakerClient].
  ///
  /// [host] is the base URL of the FileMaker Server / Cloud host, e.g.
  /// `https://fms.example.com` (no trailing slash required). [version] selects
  /// the Data API version path segment and defaults to `vLatest`.
  FileMakerClient({
    required String host,
    required this.database,
    required this.username,
    required this.password,
    this.version = 'vLatest',
    http.Client? httpClient,
  })  : _host = host.replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final String _host;

  /// The hosted database name (the `.fmp12` file name, without extension).
  final String database;

  /// Account name used to authenticate.
  final String username;

  /// Password used to authenticate.
  final String password;

  /// Data API version path segment, e.g. `vLatest` or `v1`.
  final String version;

  final http.Client _http;
  final bool _ownsClient;

  String? _token;

  /// The current session token, if logged in. Exposed for diagnostics.
  @visibleForTesting
  String? get token => _token;

  String get _base =>
      '$_host/fmi/data/$version/databases/${Uri.encodeComponent(database)}';

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /// Logs in and stores a session token. Called automatically when needed,
  /// but can be invoked explicitly to validate credentials up front.
  Future<void> login() async {
    final uri = Uri.parse('$_base/sessions');
    final basic = base64Encode(utf8.encode('$username:$password'));
    final res = await _send(
      () => _http.post(
        uri,
        headers: {
          'Authorization': 'Basic $basic',
          'Content-Type': 'application/json',
        },
        body: '{}',
      ),
    );
    final body = _decode(res);
    _throwIfError(body, res.statusCode, auth: true);
    _token = (body['response'] as Map)['token'] as String;
  }

  /// Logs out and releases the server session. Safe to call when not logged in.
  Future<void> logout() async {
    final token = _token;
    if (token == null) return;
    final uri = Uri.parse('$_base/sessions/$token');
    try {
      await _http.delete(uri);
    } finally {
      _token = null;
    }
  }

  /// Closes the underlying HTTP client if it was created internally.
  ///
  /// Does not close a client passed in via the constructor; the caller owns it.
  void close() {
    if (_ownsClient) _http.close();
  }

  // ---------------------------------------------------------------------------
  // Records
  // ---------------------------------------------------------------------------

  /// Creates a record on [layout] from [fieldData]. Returns the new recordId.
  Future<String> createRecord({
    required String layout,
    required Map<String, dynamic> fieldData,
  }) async {
    final body = await _authed(
      (token) => _http.post(
        Uri.parse('$_base/layouts/${Uri.encodeComponent(layout)}/records'),
        headers: _jsonHeaders(token),
        body: jsonEncode({'fieldData': fieldData}),
      ),
    );
    return (body['response'] as Map)['recordId'] as String;
  }

  /// Edits the record [recordId] on [layout] with [fieldData].
  ///
  /// Pass [modId] to make the edit conditional on the record not having
  /// changed since you read it (optimistic locking).
  Future<void> editRecord({
    required String layout,
    required String recordId,
    required Map<String, dynamic> fieldData,
    String? modId,
  }) async {
    await _authed(
      (token) => _http.patch(
        Uri.parse(
          '$_base/layouts/${Uri.encodeComponent(layout)}/records/$recordId',
        ),
        headers: _jsonHeaders(token),
        body: jsonEncode({
          'fieldData': fieldData,
          if (modId != null) 'modId': modId,
        }),
      ),
    );
  }

  /// Deletes the record [recordId] on [layout].
  Future<void> deleteRecord({
    required String layout,
    required String recordId,
  }) async {
    await _authed(
      (token) => _http.delete(
        Uri.parse(
          '$_base/layouts/${Uri.encodeComponent(layout)}/records/$recordId',
        ),
        headers: _jsonHeaders(token),
      ),
    );
  }

  /// Gets a single record by [recordId] from [layout].
  Future<FileMakerRecord> getRecord({
    required String layout,
    required String recordId,
  }) async {
    final body = await _authed(
      (token) => _http.get(
        Uri.parse(
          '$_base/layouts/${Uri.encodeComponent(layout)}/records/$recordId',
        ),
        headers: _jsonHeaders(token),
      ),
    );
    final data = (body['response'] as Map)['data'] as List;
    return FileMakerRecord.fromJson(
      Map<String, dynamic>.from(data.first as Map),
    );
  }

  /// Gets a range of records from [layout].
  ///
  /// [offset] is 1-based per the Data API. [limit] caps the page size.
  Future<FoundSet> getRecords({
    required String layout,
    int offset = 1,
    int limit = 100,
    List<SortOrder> sort = const [],
  }) async {
    final params = <String, String>{
      '_offset': '$offset',
      '_limit': '$limit',
      if (sort.isNotEmpty)
        '_sort': jsonEncode(sort.map((s) => s.toJson()).toList()),
    };
    final body = await _authed(
      (token) => _http.get(
        Uri.parse('$_base/layouts/${Uri.encodeComponent(layout)}/records')
            .replace(queryParameters: params),
        headers: _jsonHeaders(token),
      ),
    );
    return _foundSet(body);
  }

  // ---------------------------------------------------------------------------
  // Find
  // ---------------------------------------------------------------------------

  /// Performs a find on [layout].
  ///
  /// [query] is a list of request maps; each map is one find request and
  /// multiple maps are OR-ed together. Add `'omit': 'true'` to a request to
  /// omit matches. Example: `[{'state': 'NSW'}, {'state': 'VIC', 'omit': 'true'}]`.
  ///
  /// To retrieve all records unconditionally, use [getRecords] instead. The
  /// Data API rejects a find with empty criteria, so this method throws an
  /// [ArgumentError] if [query] is empty or contains only empty requests.
  ///
  /// Returns an empty [FoundSet] when nothing matches rather than throwing,
  /// so callers can branch on [FoundSet.isEmpty].
  Future<FoundSet> find({
    required String layout,
    required List<Map<String, dynamic>> query,
    List<SortOrder> sort = const [],
    int offset = 1,
    int limit = 100,
  }) async {
    final hasCriteria = query.any(
      (request) => request.keys
          .any((key) => key != 'omit' && '${request[key]}'.isNotEmpty),
    );
    if (!hasCriteria) {
      throw ArgumentError.value(
        query,
        'query',
        'Find requires at least one non-empty criterion. To retrieve all '
            'records, use getRecords() instead.',
      );
    }
    final payload = <String, dynamic>{
      'query': query,
      'offset': '$offset',
      'limit': '$limit',
      if (sort.isNotEmpty) 'sort': sort.map((s) => s.toJson()).toList(),
    };
    try {
      final body = await _authed(
        (token) => _http.post(
          Uri.parse('$_base/layouts/${Uri.encodeComponent(layout)}/_find'),
          headers: _jsonHeaders(token),
          body: jsonEncode(payload),
        ),
      );
      return _foundSet(body);
    } on FileMakerNoRecordsException {
      return const FoundSet(
        records: [],
        totalRecordCount: 0,
        foundCount: 0,
        returnedCount: 0,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Scripts & metadata
  // ---------------------------------------------------------------------------

  /// Runs a FileMaker [script] on [layout], optionally passing [param].
  /// Returns the script result and error as reported by the host.
  Future<({String? result, String? error})> runScript({
    required String layout,
    required String script,
    String? param,
  }) async {
    final uri = Uri.parse(
      '$_base/layouts/${Uri.encodeComponent(layout)}/script/'
      '${Uri.encodeComponent(script)}',
    ).replace(
      queryParameters: param != null ? {'script.param': param} : null,
    );
    final body = await _authed(
      (token) => _http.get(uri, headers: _jsonHeaders(token)),
    );
    final response = body['response'] as Map;
    return (
      result: response['scriptResult'] as String?,
      error: response['scriptError'] as String?,
    );
  }

  /// Returns layout metadata (field names, value lists, portal info).
  Future<Map<String, dynamic>> layoutMetadata({required String layout}) async {
    final body = await _authed(
      (token) => _http.get(
        Uri.parse('$_base/layouts/${Uri.encodeComponent(layout)}'),
        headers: _jsonHeaders(token),
      ),
    );
    return Map<String, dynamic>.from(body['response'] as Map);
  }

  /// Returns the names of all layouts in the database.
  ///
  /// Only layouts accessible to the authenticated account's privilege set are
  /// returned, and layouts hidden from the layout menu may be omitted. This is
  /// not necessarily every layout in the file; a layout absent from this list
  /// can still be used by name in other calls if the account has access to its
  /// underlying table.
  Future<List<String>> layouts() async {
    final body = await _authed(
      (token) => _http.get(
        Uri.parse('$_base/layouts'),
        headers: _jsonHeaders(token),
      ),
    );
    final list = (body['response'] as Map)['layouts'] as List;
    return list
        .map((e) => (e as Map)['name'] as String)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Map<String, String> _jsonHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Runs [request] with a valid token, logging in if needed and retrying once
  /// on an auth failure (expired / invalidated token).
  Future<Map<String, dynamic>> _authed(
    Future<http.Response> Function(String token) request,
  ) async {
    if (_token == null) await login();
    var res = await _send(() => request(_token!));
    var body = _decode(res);

    if (_isAuthError(body, res.statusCode)) {
      _token = null;
      await login();
      res = await _send(() => request(_token!));
      body = _decode(res);
    }

    _throwIfError(body, res.statusCode);
    return body;
  }

  Future<http.Response> _send(Future<http.Response> Function() fn) async {
    try {
      return await fn();
    } on http.ClientException catch (e) {
      throw FileMakerTransportException(e.message);
    } catch (e) {
      throw FileMakerTransportException('$e');
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {
      throw FileMakerTransportException(
        'Non-JSON response (HTTP ${res.statusCode})',
        code: res.statusCode,
      );
    }
  }

  FoundSet _foundSet(Map<String, dynamic> body) {
    final response = body['response'] as Map;
    final data = (response['data'] as List?) ?? const [];
    final info = (response['dataInfo'] as Map?) ?? const {};
    return FoundSet(
      records: data
          .map(
            (e) =>
                FileMakerRecord.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      totalRecordCount: int.tryParse('${info['totalRecordCount']}') ?? 0,
      foundCount: int.tryParse('${info['foundCount']}') ?? 0,
      returnedCount: int.tryParse('${info['returnedCount']}') ?? data.length,
    );
  }

  ({int? code, String message})? _firstMessage(Map<String, dynamic> body) {
    final messages = body['messages'];
    if (messages is! List || messages.isEmpty) return null;
    final m = messages.first as Map;
    final codeStr = '${m['code']}';
    return (code: int.tryParse(codeStr), message: '${m['message']}');
  }

  bool _isAuthError(Map<String, dynamic> body, int status) {
    final m = _firstMessage(body);
    // 952 = invalid token; 1631 = login failed.
    return m != null && (m.code == 952 || status == 401);
  }

  void _throwIfError(
    Map<String, dynamic> body,
    int status, {
    bool auth = false,
  }) {
    final m = _firstMessage(body);
    if (m == null) {
      if (status >= 400) {
        throw FileMakerTransportException('HTTP $status', code: status);
      }
      return;
    }
    // FileMaker reports success as code "0".
    if (m.code == 0) return;
    if (m.code == 401) {
      throw FileMakerNoRecordsException(m.message);
    }
    if (auth || m.code == 952 || m.code == 212 || m.code == 1631) {
      throw FileMakerAuthException(m.message, code: m.code);
    }
    throw FileMakerException(m.message, code: m.code);
  }
}
