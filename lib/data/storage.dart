import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../model/library.dart';
import '../model/session.dart';

/// Rohes Lesen/Schreiben — abstrahiert, damit Tests ohne Dateisystem laufen.
abstract class StorageBackend {
  Future<String?> read();
  Future<void> write(String contents);
}

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

class MemoryStorageBackend implements StorageBackend {
  MemoryStorageBackend([this._contents]);

  String? _contents;

  @override
  Future<String?> read() async => _contents;

  @override
  Future<void> write(String contents) async => _contents = contents;
}

/// Der gesamte persistierte Zustand.
class AppSnapshot {
  const AppSnapshot({
    this.library = const Library(),
    this.progress = const {},
    this.sessions = const [],
    this.settings = const {},
  });

  final Library library;

  /// programId -> Fortschritt.
  final Map<String, ProgramProgress> progress;

  final List<SessionLog> sessions;

  /// Kleinkram, der nicht zur Bibliothek gehört — derzeit der API-Schlüssel.
  ///
  /// Liegt im selben Klartext-Speicher wie alles andere. Für eine App, die
  /// einem einzelnen Menschen gehört, ist das vertretbar; auf Android liegt
  /// die Datei im privaten App-Verzeichnis. Wer den Schlüssel härter schützen
  /// will, müsste ihn in den Schlüsselbund des Systems auslagern.
  final Map<String, String> settings;

  AppSnapshot copyWith({
    Library? library,
    Map<String, ProgramProgress>? progress,
    List<SessionLog>? sessions,
    Map<String, String>? settings,
  }) => AppSnapshot(
    library: library ?? this.library,
    progress: progress ?? this.progress,
    sessions: sessions ?? this.sessions,
    settings: settings ?? this.settings,
  );

  Map<String, dynamic> toJson() => {
    'version': kBundleVersion,
    'library': library.toBundle().toJson(),
    'progress': progress.values.map((e) => e.toJson()).toList(),
    'sessions': sessions.map((e) => e.toJson()).toList(),
    if (settings.isNotEmpty) 'settings': settings,
  };

  static AppSnapshot fromJson(Map<String, dynamic> json) {
    final bundle = json['library'] == null
        ? const Bundle()
        : Bundle.fromJson(json['library'] as Map<String, dynamic>);

    final progress = <String, ProgramProgress>{};
    for (final raw in (json['progress'] as List<dynamic>? ?? const [])) {
      final entry = ProgramProgress.fromJson(raw as Map<String, dynamic>);
      progress[entry.programId] = entry;
    }

    return AppSnapshot(
      library: const Library().merge(bundle),
      progress: progress,
      sessions: (json['sessions'] as List<dynamic>? ?? const [])
          .map((e) => SessionLog.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      settings: (json['settings'] as Map<String, dynamic>? ?? const {}).map(
        (k, v) => MapEntry(k, v.toString()),
      ),
    );
  }
}

class Store {
  Store(this.backend);

  final StorageBackend backend;

  Future<AppSnapshot?> load() async {
    final raw = await backend.read();
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return AppSnapshot.fromJson(decoded);
  }

  Future<void> save(AppSnapshot snapshot) async {
    await backend.write(jsonEncode(snapshot.toJson()));
  }
}
