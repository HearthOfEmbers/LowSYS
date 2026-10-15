import 'dart:io';
import 'dart:typed_data';

/// Writes the figure PNG. Without `path_provider` (no new downloads): Windows uses the Downloads folder, falling back
/// to Documents; Android the app's external files folder; others the temp dir.
Future<String> writeFigureBytes(Uint8List bytes, String name) async {
  Directory dir;
  final env = Platform.environment;
  if (Platform.isWindows) {
    final home = env['USERPROFILE'] ?? '.';
    dir = Directory('$home\\Downloads');
    if (!dir.existsSync()) dir = Directory('$home\\Documents');
  } else if (Platform.isAndroid) {
    dir = Directory('/storage/emulated/0/Android/data/dev.lowsys.lowsys_app/files/figures');
  } else {
    dir = Directory((env['HOME'] != null) ? '${env['HOME']}/Downloads' : Directory.systemTemp.path);
  }
  try {
    dir.createSync(recursive: true);
  } on Object {
    dir = Directory.systemTemp;
  }
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  f.writeAsBytesSync(bytes);
  return f.path;
}
