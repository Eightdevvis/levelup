import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/library.dart';

/// Wo der gemeinsame Katalog liegt.
///
/// Bewusst eine rohe Datei im Repo statt eines Servers: nichts zu betreiben,
/// nichts das ausfällt, und ein neuer Plan kommt per Pull Request dazu.
const String kOpenLibraryBase =
    'https://raw.githubusercontent.com/Eightdevvis/levelup/main/library';

/// Ein Eintrag im Katalog — nur so viel, wie die Liste braucht.
///
/// Der eigentliche Plan liegt in einer eigenen Datei und wird erst geholt,
/// wenn man ihn wirklich will. Sonst müsste die App den gesamten Bestand
/// herunterladen, um vier Zeilen anzuzeigen.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    required this.file,
    this.domain = 'allgemein',
    this.description,
    this.author,
    this.weeks = 0,
    this.phases = 0,
    this.exercises = 0,
    this.tags = const [],
  });

  final String id;
  final String name;

  /// Dateiname relativ zum Katalog.
  final String file;

  final String domain;
  final String? description;
  final String? author;
  final int weeks;
  final int phases;
  final int exercises;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'file': file,
    'domain': domain,
    if (description != null) 'description': description,
    if (author != null) 'author': author,
    'weeks': weeks,
    'phases': phases,
    'exercises': exercises,
    if (tags.isNotEmpty) 'tags': tags,
  };

  static CatalogEntry fromJson(Map<String, dynamic> json) => CatalogEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    file: json['file'] as String,
    domain: json['domain'] as String? ?? 'allgemein',
    description: json['description'] as String?,
    author: json['author'] as String?,
    weeks: (json['weeks'] as num?)?.round() ?? 0,
    phases: (json['phases'] as num?)?.round() ?? 0,
    exercises: (json['exercises'] as num?)?.round() ?? 0,
    tags: (json['tags'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false),
  );
}

/// Fehler, die dem Nutzer erklärbar sind — kein roher Stacktrace.
class OpenLibraryException implements Exception {
  const OpenLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Holt Katalog und Programme aus der offenen Bibliothek.
class OpenLibraryClient {
  OpenLibraryClient({http.Client? client, this.base = kOpenLibraryBase})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String base;

  Future<List<CatalogEntry>> fetchCatalog() async {
    final body = await _get('$base/index.json');
    final decoded = jsonDecode(body);

    // Sowohl eine nackte Liste als auch ein Objekt mit "programs" annehmen —
    // das Format soll wachsen können, ohne alte App-Versionen zu brechen.
    final list = decoded is List
        ? decoded
        : (decoded as Map<String, dynamic>)['programs'] as List<dynamic>? ??
              const [];

    return list
        .map((e) => CatalogEntry.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Lädt das vollständige Bundle zu einem Katalogeintrag.
  Future<Bundle> fetchBundle(CatalogEntry entry) async {
    final body = await _get('$base/${entry.file}');
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const OpenLibraryException('Der Plan hat kein gültiges Format.');
    }
    return Bundle.fromJson(decoded);
  }

  Future<String> _get(String url) async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      throw OpenLibraryException('Kein Zugriff auf die Bibliothek: $e');
    }

    if (response.statusCode == 404) {
      throw const OpenLibraryException(
        'Die Bibliothek ist unter dieser Adresse nicht erreichbar (404).',
      );
    }
    if (response.statusCode != 200) {
      throw OpenLibraryException(
        'Die Bibliothek antwortete mit ${response.statusCode}.',
      );
    }
    // Nicht response.body: das rät die Kodierung aus dem Header und macht aus
    // Umlauten Fragezeichen, wenn der kein charset mitschickt.
    return utf8.decode(response.bodyBytes);
  }

  void close() => _client.close();
}
