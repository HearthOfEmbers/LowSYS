import 'save_store.dart';

/// Web: no file system. The browser build keeps settings and sandbox slots in memory for the session
/// (docs/DEVIATIONS.md "M10 (coder, 2026-10-13)").
SaveStore? openSaveStore() => MemorySaveStore();
