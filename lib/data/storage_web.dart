import 'package:web/web.dart' as web;

import 'storage.dart';

/// Der Speicher im Browser.
StorageBackend plattformBackend() => WebStorageBackend();

/// Legt den Zustand in `localStorage` ab.
///
/// Kein IndexedDB: der gesamte Zustand ist ein JSON-Dokument von wenigen
/// hundert Kilobyte, und `localStorage` ist der Weg, der ohne Umstände
/// funktioniert. Wird es je zu groß, fällt das beim Schreiben auf.
class WebStorageBackend implements StorageBackend {
  WebStorageBackend({this.key = 'programs_store'});

  final String key;

  @override
  Future<String?> read() async => web.window.localStorage.getItem(key);

  @override
  Future<void> write(String contents) async =>
      web.window.localStorage.setItem(key, contents);
}
