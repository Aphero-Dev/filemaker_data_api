import 'package:filemaker_data_api/filemaker_data_api.dart';

Future<void> main() async {
  final fm = FileMakerClient(
    host: 'https://fms.example.com',
    database: 'Contacts',
    username: 'admin',
    password: 'secret',
  );

  try {
    // Create.
    final id = await fm.createRecord(
      layout: 'Contacts',
      fieldData: {'name': 'Jane Doe', 'state': 'NSW'},
    );
    print('Created record $id');

    // Find (OR of two requests, second omits VIC matches).
    final found = await fm.find(
      layout: 'Contacts',
      query: [
        {'state': 'NSW'},
        {'state': 'VIC', 'omit': 'true'},
      ],
      sort: [const SortOrder('name')],
      limit: 50,
    );

    if (found.isEmpty) {
      print('No matching records.');
    } else {
      print('Found ${found.foundCount} of ${found.totalRecordCount} total');
      for (final r in found.records) {
        print('  ${r.recordId}: ${r['name']} (${r['state']})');
      }
    }

    // Edit.
    await fm.editRecord(
      layout: 'Contacts',
      recordId: id,
      fieldData: {'state': 'QLD'},
    );

    // Run a server-side script.
    final script = await fm.runScript(
      layout: 'Contacts',
      script: 'RecalculateTotals',
      param: id,
    );
    print('Script result: ${script.result}, error: ${script.error}');

    // Delete.
    await fm.deleteRecord(layout: 'Contacts', recordId: id);
  } on FileMakerAuthException catch (e) {
    print('Auth failed: $e');
  } on FileMakerException catch (e) {
    print('FileMaker error: $e');
  } finally {
    await fm.logout();
    fm.close();
  }
}
