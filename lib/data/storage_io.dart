import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage.dart';

/// Der Speicher auf einem Gerät mit Dateisystem.
StorageBackend plattformBackend() => FileStorageBackend();

class FileStorageBackend implements StorageBackend {
  FileStorageBackend({this.fileName = 'programs_store.json'});

  final String fileName;
  File? _cached;

  Future<File> _file() async {
    final cached = _cached;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    _cached = file;
    return file;
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String contents) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // Erst daneben schreiben, dann umbenennen: ein Absturz mitten im Schreiben
    // darf nicht die gesamte Bibliothek zerlegen.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(file.path);
  }
}
