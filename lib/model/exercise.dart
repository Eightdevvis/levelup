import 'set_spec.dart';
import 'target.dart';

enum MediaKind { image, animation, video, audio, link }

MediaKind _mediaKindFromString(String? value) => switch (value) {
  'animation' => MediaKind.animation,
  'video' => MediaKind.video,
  'audio' => MediaKind.audio,
  'link' => MediaKind.link,
  _ => MediaKind.image,
};

/// Ein Medium zu einer Übung. [uri] darf lokal (`file:`, `asset:`) oder remote
/// sein — die App lädt nur, was sie kennt, und zeigt sonst den Verweis an.
class Media {
  const Media({required this.kind, required this.uri, this.caption});

  final MediaKind kind;
  final String uri;
  final String? caption;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'uri': uri,
    if (caption != null) 'caption': caption,
  };

  static Media fromJson(Map<String, dynamic> json) => Media(
    kind: _mediaKindFromString(json['kind'] as String?),
    uri: json['uri'] as String,
    caption: json['caption'] as String?,
  );
}

/// Die wiederverwendbare Übung — das zentrale Objekt der ganzen App.
///
/// Bewusst ohne Domänen-Annahmen: `domain` ist ein freies Tag, kein Enum.
/// Eine Übung kennt ihren eigenen Standard-Ansatz ([defaultSets]), wird aber
/// von jedem Programm überschrieben, das sie einsetzt.
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    this.domain = 'allgemein',
    this.summary,
    this.instructions = const [],
    this.benefits = const [],
    this.cues = const [],
    this.media = const [],
    this.requirements = const [],
    this.tags = const [],
    this.defaultSets = const [],
    this.source,
  });

  final String id;
  final String name;

  /// Freies Tag, z.B. "geige", "kraft", "gehoerbildung", "zeichnen".
  final String domain;

  /// Ein bis zwei Sätze: worum geht es.
  final String? summary;

  /// Schritt-für-Schritt-Anleitung.
  final List<String> instructions;

  /// Wofür das gut ist — der Teil, der Motivation trägt.
  final List<String> benefits;

  /// Kurze Hinweise, die während der Ausführung eingeblendet werden.
  final List<String> cues;

  final List<Media> media;

  /// Was man braucht: "Metronom", "Klavier", "Kurzhantel".
  final List<String> requirements;

  final List<String> tags;

  /// Vorschlag, wenn die Übung ohne Programm-Kontext ausgeführt wird.
  final List<SetSpec> defaultSets;

  /// Herkunft/Attribution, z.B. bei importierten Datenbanken.
  final String? source;

  Media? get primaryImage {
    for (final item in media) {
      if (item.kind == MediaKind.image || item.kind == MediaKind.animation) {
        return item;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'domain': domain,
    if (summary != null) 'summary': summary,
    if (instructions.isNotEmpty) 'instructions': instructions,
    if (benefits.isNotEmpty) 'benefits': benefits,
    if (cues.isNotEmpty) 'cues': cues,
    if (media.isNotEmpty) 'media': media.map((e) => e.toJson()).toList(),
    if (requirements.isNotEmpty) 'requirements': requirements,
    if (tags.isNotEmpty) 'tags': tags,
    if (defaultSets.isNotEmpty)
      'defaultSets': defaultSets.map((e) => e.toJson()).toList(),
    if (source != null) 'source': source,
  };

  static Exercise fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String,
    name: json['name'] as String,
    domain: json['domain'] as String? ?? 'allgemein',
    summary: json['summary'] as String?,
    instructions: _stringList(json['instructions']),
    benefits: _stringList(json['benefits']),
    cues: _stringList(json['cues']),
    media: (json['media'] as List<dynamic>? ?? const [])
        .map((e) => Media.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    requirements: _stringList(json['requirements']),
    tags: _stringList(json['tags']),
    defaultSets: (json['defaultSets'] as List<dynamic>? ?? const [])
        .map((e) => SetSpec.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    source: json['source'] as String?,
  );

  /// Fallback, damit ein kaputter oder unvollständiger Import den Player
  /// nicht zum Absturz bringt, sondern sichtbar wird.
  static Exercise placeholder(String id) => Exercise(
    id: id,
    name: 'Unbekannte Übung',
    summary: 'Diese Übung fehlt in der Bibliothek (id: $id).',
    defaultSets: const [SetSpec(target: OpenTarget())],
  );

  static List<String> _stringList(dynamic value) =>
      (value as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false);
}
