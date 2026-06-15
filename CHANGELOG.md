## 0.1.0

- Initial release.
- Session management with automatic login and one-shot token refresh on expiry.
- Records: create, edit (with optional `modId` optimistic lock), delete, get, get range.
- Find requests with sort, offset, limit, omit, and OR-ed requests.
- Empty found sets returned as an empty `FoundSet` rather than throwing.
- Run server-side scripts with parameters.
- Layout and database metadata (`layoutMetadata`, `layouts`).
- Typed exceptions: `FileMakerException`, `FileMakerAuthException`,
  `FileMakerNoRecordsException`, `FileMakerTransportException`.
