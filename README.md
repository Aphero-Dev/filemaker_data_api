# filemaker_data_api

A typed Dart client for the [Claris FileMaker Data API](https://help.claris.com/en/data-api-guide/). Works anywhere Dart runs: Flutter (iOS, Android, macOS, Windows, web), server-side Dart, and CLI tools.

> Not affiliated with or endorsed by Claris International Inc. "FileMaker" and "Claris" are trademarks of Claris International Inc.

## Features

- Session token managed for you: logs in on first use, refreshes once automatically if the token expires.
- Records: create, edit (with optional `modId` optimistic locking), delete, get, get range.
- Find requests with sort, paging, omit, and OR-ed requests.
- Empty found sets come back as an empty `FoundSet` instead of throwing, so "no matches" is easy to branch on.
- Run server-side scripts with parameters.
- Layout and database metadata.
- Typed exceptions instead of raw HTTP juggling.

## Install

```yaml
dependencies:
  filemaker_data_api: ^0.1.0
```

## Usage

```dart
import 'package:filemaker_data_api/filemaker_data_api.dart';

final fm = FileMakerClient(
  host: 'https://fms.example.com',
  database: 'Contacts',
  username: 'admin',
  password: 'secret',
);

// Create
final id = await fm.createRecord(
  layout: 'Contacts',
  fieldData: {'name': 'Jane Doe', 'state': 'NSW'},
);

// Find
final found = await fm.find(
  layout: 'Contacts',
  query: [
    {'state': 'NSW'},
    {'state': 'VIC', 'omit': 'true'},
  ],
  sort: [const SortOrder('name')],
  limit: 50,
);

for (final r in found.records) {
  print('${r.recordId}: ${r['name']}');
}

await fm.logout();
fm.close();
```

## Error handling

| Exception | When |
| --- | --- |
| `FileMakerAuthException` | Bad credentials or rejected token |
| `FileMakerNoRecordsException` | FileMaker error 401 (raised by record ops, not by `find`) |
| `FileMakerTransportException` | Host unreachable or non-JSON response |
| `FileMakerException` | Any other FileMaker error code |

```dart
try {
  await fm.getRecord(layout: 'Contacts', recordId: '999');
} on FileMakerNoRecordsException {
  // handle not found
} on FileMakerException catch (e) {
  print('${e.code}: ${e.message}');
}
```

## Requirements

- FileMaker Server or FileMaker Cloud with the Data API enabled.
- A FileMaker account with the `fmrest` extended privilege on its privilege set.

## Roadmap

- Container field upload/download.
- Global field values.
- Companion package `filemaker_odata_api` for the OData v4 interface.

## License

MIT
