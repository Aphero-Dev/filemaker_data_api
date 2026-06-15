import 'dart:convert';

import 'package:filemaker_data_api/filemaker_data_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

const _ok = {
  'messages': [
    {'code': '0', 'message': 'OK'},
  ],
};

void main() {
  group('login', () {
    test('stores token from sessions response', () async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, contains('/sessions'));
        expect(req.headers['Authorization'], startsWith('Basic '));
        return _json({
          ..._ok,
          'response': {'token': 'TKN123'},
        });
      });

      final fm = FileMakerClient(
        host: 'https://fms.example.com',
        database: 'Contacts',
        username: 'admin',
        password: 'secret',
        httpClient: mock,
      );

      await fm.login();
      expect(fm.token, 'TKN123');
    });

    test('throws FileMakerAuthException on bad credentials', () async {
      final mock = MockClient(
        (req) async => _json({
          'messages': [
            {'code': '212', 'message': 'Invalid account or password'},
          ],
          'response': {},
        }),
      );

      final fm = FileMakerClient(
        host: 'https://fms.example.com',
        database: 'Contacts',
        username: 'admin',
        password: 'wrong',
        httpClient: mock,
      );

      expect(fm.login, throwsA(isA<FileMakerAuthException>()));
    });
  });

  group('createRecord', () {
    test('logs in automatically then returns recordId', () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        if (req.url.path.endsWith('/sessions')) {
          return _json({
            ..._ok,
            'response': {'token': 'TKN'},
          });
        }
        expect(req.headers['Authorization'], 'Bearer TKN');
        final payload = jsonDecode(req.body) as Map;
        expect((payload['fieldData'] as Map)['name'], 'Jane');
        return _json({
          ..._ok,
          'response': {'recordId': '42', 'modId': '0'},
        });
      });

      final fm = FileMakerClient(
        host: 'https://fms.example.com',
        database: 'Contacts',
        username: 'admin',
        password: 'secret',
        httpClient: mock,
      );

      final id = await fm.createRecord(
        layout: 'Contacts',
        fieldData: {'name': 'Jane'},
      );
      expect(id, '42');
      expect(calls, 2); // login + create
    });
  });

  group('find', () {
    test('parses a found set', () async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/sessions')) {
          return _json({
            ..._ok,
            'response': {'token': 'TKN'},
          });
        }
        return _json({
          ..._ok,
          'response': {
            'dataInfo': {
              'totalRecordCount': 500,
              'foundCount': 2,
              'returnedCount': 2,
            },
            'data': [
              {
                'recordId': '1',
                'modId': '3',
                'fieldData': {'name': 'John', 'state': 'NSW'},
                'portalData': {},
              },
              {
                'recordId': '2',
                'modId': '0',
                'fieldData': {'name': 'Jack', 'state': 'NSW'},
                'portalData': {},
              },
            ],
          },
        });
      });

      final fm = FileMakerClient(
        host: 'https://fms.example.com',
        database: 'Contacts',
        username: 'admin',
        password: 'secret',
        httpClient: mock,
      );

      final result = await fm.find(
        layout: 'Contacts',
        query: [
          {'state': 'NSW'},
        ],
      );
      expect(result.foundCount, 2);
      expect(result.totalRecordCount, 500);
      expect(result.records.first['name'], 'John');
      expect(result.records.first.recordId, '1');
    });

    test('returns empty found set (not throw) on error 401', () async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/sessions')) {
          return _json({
            ..._ok,
            'response': {'token': 'TKN'},
          });
        }
        return _json({
          'messages': [
            {'code': '401', 'message': 'No records match the request'},
          ],
          'response': {},
        });
      });

      final fm = FileMakerClient(
        host: 'https://fms.example.com',
        database: 'Contacts',
        username: 'admin',
        password: 'secret',
        httpClient: mock,
      );

      final result = await fm.find(
        layout: 'Contacts',
        query: [
          {'name': 'Nobody'},
        ],
      );
      expect(result.isEmpty, isTrue);
      expect(result.foundCount, 0);
    });
  });

  group('token refresh', () {
    test('re-logs in once and retries on invalid token (952)', () async {
      var sessions = 0;
      var getsBeforeRefresh = 0;
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/sessions') && req.method == 'POST') {
          sessions++;
          return _json({
            ..._ok,
            'response': {'token': 'TKN$sessions'},
          });
        }
        // First data call fails with 952, second succeeds.
        if (getsBeforeRefresh == 0) {
          getsBeforeRefresh++;
          return _json({
            'messages': [
              {'code': '952', 'message': 'Invalid FileMaker Data API token'},
            ],
            'response': {},
          });
        }
        return _json({
          ..._ok,
          'response': {
            'data': [
              {
                'recordId': '7',
                'modId': '1',
                'fieldData': {'name': 'Refreshed'},
                'portalData': {},
              }
            ],
          },
        });
      });

      final fm = FileMakerClient(
        host: 'https://fms.example.com',
        database: 'Contacts',
        username: 'admin',
        password: 'secret',
        httpClient: mock,
      );

      final rec = await fm.getRecord(layout: 'Contacts', recordId: '7');
      expect(rec['name'], 'Refreshed');
      expect(sessions, 2); // initial login + one refresh
    });
  });
}
