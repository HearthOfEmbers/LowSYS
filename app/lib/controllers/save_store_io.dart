import 'dart:io';

import 'save_store.dart';

/// One file per key. The directory is the platform's application-data folder where it can be found from the
/// environment, otherwise the temporary directory (on Android the app's private cache). Swap in
/// shared_preferences behind this interface when that dependency is approved.
class FileSaveStore implements SaveStore {
  final Directory dir;
  FileSaveStore._(this.dir);

  static FileSaveStore open() {
    final env = Platform.environment;
    final base =
        env['APPDATA'] ??
        env['XDG_DATA_HOME'] ??
        (env['HOME'] != null ? '${env['HOME']}/.local/share' : null);
    final dir = Directory(
      base != null
          ? '$base${Platform.pathSeparator}LowSYS'
          : '${Directory.systemTemp.path}${Platform.pathSeparator}LowSYS',
    );
    try {
      dir.createSync(recursive: true);
    } on FileSystemException {
      final fallback = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}LowSYS',
      )..createSync(recursive: true);
      return FileSaveStore._(fallback);
    }
    return FileSaveStore._(dir);
  }

  File _f(String key) => File(
    '${dir.path}${Platform.pathSeparator}${Uri.encodeComponent(key)}.json',
  );

  @override
  Future<String?> read(String key) async {
    final f = _f(key);
    return f.existsSync() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async =>
      _f(key).writeAsString(value, flush: true);

  @override
  Future<void> delete(String key) async {
    final f = _f(key);
    if (f.existsSync()) await f.delete();
  }

  @override
  Future<List<String>> keys() async => [
    for (final e in dir.listSync())
      if (e is File && e.path.endsWith('.json'))
        Uri.decodeComponent(e.uri.pathSegments.last.replaceAll('.json', '')),
  ];
}


/// The platform save store (a folder of JSON files).
SaveStore? openSaveStore() => FileSaveStore.open();
