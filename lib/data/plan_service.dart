import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/library.dart';
import '../model/patch.dart';

/// Fortschritt eines laufenden Auftrags.
///
/// Der Server schickt ein eigenes, kleines Protokoll statt Anthropics
/// Rohformat. Die App muss deshalb nicht wissen, wie ein `content_block_delta`
/// aussieht — und ungültige Antworten fallen schon auf dem Server auf.
sealed class PlanEvent {
  const PlanEvent();
}

/// Es wird nachgedacht. [text] ist der letzte Satz des Gedankengangs.
class PlanThinking extends PlanEvent {
  const PlanThinking(this.text);
  final String text;
}

/// Im geteilten Pool wird nach vorhandenen Bausteinen gesucht.
///
/// Das sichtbar zu machen ist Absicht: der Nutzer soll sehen, dass nicht alles
/// neu erfunden wird — und woran gerade gearbeitet wird, während nichts
/// Lesbares entsteht.
class PlanSearching extends PlanEvent {
  const PlanSearching({
    required this.tool,
    required this.terms,
    required this.hits,
  });

  final String tool;
  final List<String> terms;
  final int hits;

  String describe() {
    final was = switch (tool) {
      'uebungen' => 'Übungen',
      'plaene' => 'Pläne',
      _ => 'Plan',
    };
    final wonach = terms.isEmpty ? '' : ' zu ${terms.join(", ")}';
    return hits == 0
        ? 'Nichts Vorhandenes$wonach — wird selbst gebaut.'
        : '$hits $was$wonach gefunden.';
  }
}

/// Der Plan wird geschrieben. [chars] ist die bisherige Länge.
class PlanWriting extends PlanEvent {
  const PlanWriting(this.chars);
  final int chars;
}

/// Ein fertiger Plan.
class PlanDone extends PlanEvent {
  const PlanDone(this.bundle, {this.reused = const []});

  final Bundle bundle;

  /// Was aus dem geteilten Pool übernommen wurde.
  final List<String> reused;
}

/// Eine fertige Überarbeitung — Änderungen, kein neuer Plan.
class PlanRevised extends PlanEvent {
  const PlanRevised(this.patch);
  final PlanPatch patch;
}

/// Was das Konto noch hergibt.
class Quota {
  const Quota({
    required this.remaining,
    required this.dailyRemaining,
    required this.used,
  });

  final int remaining;
  final int dailyRemaining;
  final int used;

  bool get exhausted => remaining <= 0;

  static Quota fromJson(Map<String, dynamic> json) => Quota(
    remaining: (json['remaining'] as num?)?.round() ?? 0,
    dailyRemaining: (json['dailyRemaining'] as num?)?.round() ?? 0,
    used: (json['used'] as num?)?.round() ?? 0,
  );
}

/// Fehler, die dem Nutzer erklärbar sind. [code] erlaubt der Oberfläche, auf
/// bestimmte Fälle anders zu reagieren — etwa aufgebrauchtes Guthaben.
class PlanException implements Exception {
  const PlanException(this.message, {this.code});

  final String message;
  final String? code;

  bool get quotaExhausted => code == 'quota_exhausted' || code == 'daily_limit';

  @override
  String toString() => message;
}

/// Spricht mit der LevelUp-API.
///
/// Der Anthropic-Schlüssel liegt beim Betreiber, nicht auf dem Gerät. Die App
/// weist sich mit einem Gerätetoken aus, das sie beim ersten Start einmalig
/// bekommt — kein Konto, keine Anmeldung. Der Platz für ein späteres
/// E-Mail-Konto ist serverseitig schon vorgesehen.
class PlanService {
  PlanService({required this.baseUrl, required this.token, http.Client? client})
    : _client = client ?? http.Client();

  /// Wo die API läuft.
  static const defaultBaseUrl = 'https://levelup-api.sevendevs.workers.dev';

  final String baseUrl;
  final String token;
  final http.Client _client;

  /// Einmalige Geräteregistrierung. Liefert das Token, das danach dauerhaft
  /// gilt — es gibt keinen zweiten Weg, es zu erfahren.
  static Future<String> register({
    required String baseUrl,
    required String platform,
    http.Client? client,
  }) async {
    final web = client ?? http.Client();
    try {
      final response = await web
          .post(
            Uri.parse('$baseUrl/v1/devices'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'platform': platform}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw PlanException(_message(response.body, response.statusCode));
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final token = body['token'] as String?;
      if (token == null || token.isEmpty) {
        throw const PlanException('Die Registrierung lieferte kein Token.');
      }
      return token;
    } on PlanException {
      rethrow;
    } on Exception catch (e) {
      throw PlanException('Registrierung fehlgeschlagen: $e');
    } finally {
      if (client == null) web.close();
    }
  }

  Future<Quota> quota() async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/v1/me'),
          headers: {'authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw PlanException(
        _message(response.body, response.statusCode),
        code: _code(response.body),
      );
    }
    return Quota.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Stream<PlanEvent> generatePlan(String request) {
    if (request.trim().isEmpty) {
      return Stream.error(
        const PlanException('Beschreib erst, worum es gehen soll.'),
      );
    }
    return _stream('/v1/generate', {'request': request}, (done) {
      final raw = done['bundle'];
      if (raw is! Map<String, dynamic>) {
        throw const PlanException('Es kam kein Plan zurück.');
      }
      return PlanDone(
        _bundle(raw),
        reused: [
          for (final id in done['reused'] as List<dynamic>? ?? const [])
            if (id is String) id,
        ],
      );
    });
  }

  /// Bittet um Änderungen an einem bestehenden Plan.
  ///
  /// Zurück kommt kein neuer Plan, sondern ein Patch. Das ist der Punkt: was
  /// nicht bemängelt wurde, bleibt Zeichen für Zeichen stehen.
  Stream<PlanEvent> revisePlan(Bundle bundle, String feedback) {
    if (feedback.trim().isEmpty) {
      return Stream.error(const PlanException('Sag, was nicht passt.'));
    }
    return _stream(
      '/v1/revise',
      // Ohne den persönlichen Teil: er ist Ausgabe, nicht Eingabe, und würde
      // die Überarbeitung nur auf sich selbst beziehen.
      {'bundle': bundle.shareable.toJson(), 'feedback': feedback},
      (done) {
        final raw = done['patch'];
        if (raw is! Map<String, dynamic>) {
          throw const PlanException('Es kamen keine Änderungen zurück.');
        }
        return PlanRevised(PlanPatch.fromJson(raw));
      },
    );
  }

  /// Nimmt den Plan an: er wandert in die geteilte Bibliothek.
  ///
  /// Verschickt wird ausdrücklich die teilbare Fassung — der persönliche Teil
  /// verlässt das Gerät nicht. Der Server entfernt ihn zwar ebenfalls, aber
  /// worauf man sich verlässt, sollte man nicht erst verschicken.
  Future<void> acceptPlan(Bundle bundle) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/v1/plans/accept'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode({'bundle': bundle.shareable.toJson()}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw PlanException(
        _message(response.body, response.statusCode),
        code: _code(response.body),
      );
    }
  }

  /// Liest den Ereignisstrom eines Auftrags.
  ///
  /// Erzeugen und Überarbeiten unterscheiden sich nur darin, was am Ende
  /// herauskommt — deshalb steckt der Unterschied in [onDone] und nicht in
  /// zwei fast gleichen Schleifen.
  Stream<PlanEvent> _stream(
    String path,
    Map<String, dynamic> body,
    PlanEvent Function(Map<String, dynamic>) onDone,
  ) async* {
    final http.StreamedResponse response;
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl$path'))
        ..headers.addAll({
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        })
        ..body = jsonEncode(body);
      response = await _client.send(request);
    } on Exception catch (e) {
      throw PlanException('Kein Zugriff auf die LevelUp-API: $e');
    }

    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      throw PlanException(
        _message(text, response.statusCode),
        code: _code(text),
      );
    }

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;

      final Map<String, dynamic> event;
      try {
        event = jsonDecode(line.substring(6)) as Map<String, dynamic>;
      } on FormatException {
        continue; // Herzschlag oder Bruchstück
      }

      switch (event['type']) {
        case 'thinking':
          yield PlanThinking(event['text'] as String? ?? '');
        case 'writing':
          yield PlanWriting((event['chars'] as num?)?.round() ?? 0);
        case 'search':
          yield PlanSearching(
            tool: event['tool'] as String? ?? '',
            terms: [
              for (final t in event['terms'] as List<dynamic>? ?? const [])
                if (t is String) t,
            ],
            hits: (event['hits'] as num?)?.round() ?? 0,
          );
        case 'error':
          throw PlanException(
            event['message'] as String? ?? 'Unbekannter Fehler.',
            code: event['code'] as String?,
          );
        case 'done':
          yield onDone(event);
          return;
      }
    }

    // Der Strom endete ohne Ergebnis — meist eine abgerissene Verbindung.
    throw const PlanException('Die Verbindung brach ab. Bitte nochmal.');
  }

  static Bundle _bundle(Map<String, dynamic> raw) {
    try {
      return Bundle.fromJson(raw);
    } on FormatException catch (e) {
      throw PlanException('Der Plan ließ sich nicht lesen: ${e.message}');
    } catch (e) {
      throw PlanException('Der Plan ließ sich nicht lesen: $e');
    }
  }

  static String? _code(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['error'] as Map<String, dynamic>?)?['code'] as String?;
      }
    } on FormatException {
      // kein JSON
    }
    return null;
  }

  static String _message(String body, int status) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message =
            (decoded['error'] as Map<String, dynamic>?)?['message'] as String?;
        if (message != null) return message;
      }
    } on FormatException {
      // kein JSON — dann eben nur der Status.
    }
    return switch (status) {
      401 => 'Dieses Gerät ist nicht angemeldet.',
      429 => 'Zu viele Anfragen. Kurz warten und nochmal.',
      >= 500 => 'Der Dienst ist gerade nicht erreichbar.',
      _ => 'Die API antwortete mit $status.',
    };
  }

  void close() => _client.close();
}
