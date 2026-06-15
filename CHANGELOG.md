## 0.1.1

- Add `topics` to pubspec for discoverability.
- README: cross-reference the companion `filemaker_odata_api` package.

## 0.1.0

- Initial release.
- Session management with automatic login and one-shot token refresh on expiry.
- Records: create, edit (with optional `modId` optimistic lock), delete, get, get range.
- Find requests with sort, offset, limit, omit, and OR-ed requests.
- `find` throws `ArgumentError` on empty criteria and points callers to
  `getRecords` for unconditional retrieval.
- Empty found sets returned as an empty `FoundSet` rather than throwing.
- Run server-side scripts with parameters.
- Layout and database metadata (`layoutMetadata`, `layouts`). Note `layouts`
  returns only layouts accessible to the authenticated account.
- Typed exceptions: `FileMakerException`, `FileMakerAuthException`,
  `FileMakerNoRecordsException`, `FileMakerTransportException`.
