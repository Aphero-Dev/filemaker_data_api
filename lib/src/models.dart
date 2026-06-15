import 'package:meta/meta.dart';

/// Sort direction for a [SortOrder].
enum SortDirection {
  /// Ascending order.
  ascend,

  /// Descending order.
  descend,
}

/// A single sort instruction applied to a find or record range request.
@immutable
class SortOrder {
  /// Creates a [SortOrder] for [fieldName] in the given [direction].
  const SortOrder(this.fieldName, [this.direction = SortDirection.ascend]);

  /// The field to sort by.
  final String fieldName;

  /// The direction to sort in.
  final SortDirection direction;

  /// Serializes to the shape the Data API expects in a `sort` array.
  Map<String, String> toJson() => {
        'fieldName': fieldName,
        'sortOrder':
            direction == SortDirection.ascend ? 'ascend' : 'descend',
      };
}

/// A single FileMaker record returned by the Data API.
@immutable
class FileMakerRecord {
  /// Creates a [FileMakerRecord].
  const FileMakerRecord({
    required this.recordId,
    required this.modId,
    required this.fieldData,
    this.portalData = const {},
  });

  /// Builds a record from one entry of the Data API `data` array.
  factory FileMakerRecord.fromJson(Map<String, dynamic> json) {
    return FileMakerRecord(
      recordId: json['recordId'] as String,
      modId: json['modId'] as String,
      fieldData: Map<String, dynamic>.from(json['fieldData'] as Map),
      portalData: (json['portalData'] as Map?)?.map(
            (key, value) => MapEntry(
              key as String,
              (value as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
            ),
          ) ??
          const {},
    );
  }

  /// The internal record id used for edit/delete/get operations.
  final String recordId;

  /// The modification id, used for optimistic-lock edits.
  final String modId;

  /// The record's field values keyed by field name.
  final Map<String, dynamic> fieldData;

  /// Related records keyed by portal (table occurrence) name.
  final Map<String, List<Map<String, dynamic>>> portalData;

  /// Convenience accessor for a field value.
  dynamic operator [](String fieldName) => fieldData[fieldName];
}

/// The result of a find or get-range request: records plus paging info.
@immutable
class FoundSet {
  /// Creates a [FoundSet].
  const FoundSet({
    required this.records,
    required this.totalRecordCount,
    required this.foundCount,
    required this.returnedCount,
  });

  /// The records on this page of results.
  final List<FileMakerRecord> records;

  /// Total records in the table (not just the found set).
  final int totalRecordCount;

  /// Total records matching the request.
  final int foundCount;

  /// Number of records actually returned on this page.
  final int returnedCount;

  /// Whether the found set is empty.
  bool get isEmpty => records.isEmpty;
}
