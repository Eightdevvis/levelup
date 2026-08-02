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
    this.description,
    this.benefits = const [],
    this.cues = const [],
    this.media = const [],
    this.equipment = const [],
    this.tags = const [],
    this.defaultSets = const [],
    this.source,
  });

  final String id;
  final String name;

  /// Was der Nutzer tun soll — Handlungsanweisung, kein Erklärtext.
  ///
  /// Waren früher zwei Felder, `summary` und `instructions`, und sagten beide
  /// dasselbe. Der Nutzer muss genau eine Frage beantwortet bekommen: was
  /// mache ich hier?
  final String? description;

  /// Wofür das gut ist — der Teil, der Motivation trägt.
  final List<String> benefits;

  /// Kurze Hinweise, die während der Ausführung eingeblendet werden.
  final List<String> cues;

  final List<Media> media;

  /// Was man braucht: "Metronom", "Klavier", "Kurzhantel". Leer heißt: das
  /// übliche Grundwerkzeug reicht.
  final List<String> equipment;

  final List<String> tags;

  /// Die Anleitung zeilenweise — für Ansichten, die Schritte untereinander
  /// setzen. Ein Feld, mehrere Zeilen: die Trennung ist Darstellung, nicht
  /// Datenmodell.
  List<String> get lines => description == null
      ? const []
      : description!
            .split('\n')
            .map((z) => z.trim())
            .where((z) => z.isNotEmpty)
            .toList(growable: false);

  /// Die Tätigkeit, abgeleitet aus dem ersten Tag.
  ///
  /// Ein eigenes Feld dafür gibt es nicht mehr: die Bibliothek ist flach, und
  /// was zusammengehört, ergibt sich aus den Tags. Der Prompt verlangt die
  /// Tätigkeit als ersten Tag, deshalb steht sie dort.
  String get domain => tags.isEmpty ? 'allgemein' : tags.first;

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
    if (description != null) 'description': description,
    if (benefits.isNotEmpty) 'benefits': benefits,
    if (cues.isNotEmpty) 'cues': cues,
    if (media.isNotEmpty) 'media': media.map((e) => e.toJson()).toList(),
    if (equipment.isNotEmpty) 'equipment': equipment,
    if (tags.isNotEmpty) 'tags': tags,
    if (defaultSets.isNotEmpty)
      'defaultSets': defaultSets.map((e) => e.toJson()).toList(),
    if (source != null) 'source': source,
  };

  /// Liest auch die alte Form.
  ///
  /// Auf den Geräten liegen Bibliotheken, die noch `summary`, `instructions`
  /// und `requirements` tragen. Die stillschweigend fallen zu lassen hieße,
  /// jedem seine Übungen zu leeren Hüllen zu machen — also werden sie hier
  /// übersetzt: `summary` und `instructions` zu einem `description`,
  /// `requirements` zu `equipment`. `domain` fällt weg, weil es aus den Tags
  /// kommt; steht es nicht schon dort, wird es als erster Tag aufgenommen.
  static Exercise fromJson(Map<String, dynamic> json) {
    final tags = _stringList(json['tags']);

    final alteDomain = (json['domain'] as String?)?.trim();
    if (alteDomain != null &&
        alteDomain.isNotEmpty &&
        alteDomain != 'allgemein' &&
        !tags.contains(alteDomain)) {
      tags.insert(0, alteDomain);
    }

    return Exercise(
      id: json['id'] as String,
      name: json['name'] as String,
      description: _description(json),
      benefits: _stringList(json['benefits']),
      cues: _stringList(json['cues']),
      media: (json['media'] as List<dynamic>? ?? const [])
          .map((e) => Media.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      equipment: _stringList(json['equipment']).isNotEmpty
          ? _stringList(json['equipment'])
          : _stringList(json['requirements']),
      tags: tags,
      defaultSets: (json['defaultSets'] as List<dynamic>? ?? const [])
          .map((e) => SetSpec.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      source: json['source'] as String?,
    );
  }

  /// `description`, sonst `summary` und `instructions` zusammengesetzt.
  static String? _description(Map<String, dynamic> json) {
    final neu = (json['description'] as String?)?.trim();
    if (neu != null && neu.isNotEmpty) return neu;

    final teile = <String>[
      if ((json['summary'] as String?)?.trim().isNotEmpty ?? false)
        (json['summary'] as String).trim(),
      ..._stringList(json['instructions']).where((z) => z.trim().isNotEmpty),
    ];
    return teile.isEmpty ? null : teile.join('\n');
  }

  /// Fallback, damit ein kaputter oder unvollständiger Import den Player
  /// nicht zum Absturz bringt, sondern sichtbar wird.
  static Exercise placeholder(String id) => Exercise(
    id: id,
    name: 'Unbekannte Übung',
    description: 'Diese Übung fehlt in der Bibliothek (id: $id).',
    defaultSets: const [SetSpec(target: OpenTarget())],
  );

  // Wachsend, nicht fest: `fromJson` schiebt die alte `domain` vorne ein.
  static List<String> _stringList(dynamic value) =>
      (value as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
}
