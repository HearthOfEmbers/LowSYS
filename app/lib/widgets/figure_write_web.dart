import 'dart:typed_data';

/// Web: figure export needs a download, which waits for a web-only dependency (docs/DEVIATIONS.md M10).
Future<String> writeFigureBytes(Uint8List bytes, String name) async =>
    throw UnsupportedError('Figure export is not available in the browser build');
