import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/library.dart';

/// Fortschritt einer laufenden Plan-Erzeugung.
///
/// Der Server reicht den Ereignisstrom von Anthropic unverändert durch, damit
/// die App zeigen kann, woran gerade gearbeitet wird — eine Diagnose dauert
/// Minuten, bevor das erste Zeichen Plan kommt.
sealed class PlanEvent {
  const PlanEvent();
}

/// Es wird nachgedacht. [text] ist die Zusammenfassung des Gedankengangs.
class PlanThinking extends PlanEvent {
  const PlanThinking(this.text);
  final String text;
}

/// Der Plan wird geschrieben. [chars] ist die bisherige Länge.
class PlanWriting extends PlanEvent {
  const PlanWriting(this.chars);
  final int chars;
}

class PlanDone extends PlanEvent {
  const PlanDone(this.bundle);
  final Bundle bundle;
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

  /// Wo die API läuft. Wird beim Ausrollen gesetzt.
  static const defaultBaseUrl = 'https://levelup-api.workers.dev';

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
      throw PlanException(_message(response.body, response.statusCode));
    }
    return Quota.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Stream<PlanEvent> generatePlan(String request) async* {
    if (request.trim().isEmpty) {
      throw const PlanException('Beschreib erst, worum es gehen soll.');
    }

    final http.StreamedResponse response;
    try {
      final req = http.Request('POST', Uri.parse('$baseUrl/v1/generate'))
        ..headers.addAll({
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        })
        ..body = jsonEncode({'request': request});
      response = await _client.send(req);
    } on Exception catch (e) {
      throw PlanException('Kein Zugriff auf die LevelUp-API: $e');
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw PlanException(
        _message(body, response.statusCode),
        code: _code(body),
      );
    }

    final json = StringBuffer();
    String? stopReason;
    var thinking = '';

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final raw = line.substring(6);
      if (raw == '[DONE]') break;

      final Map<String, dynamic> event;
      try {
        event = jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException {
        continue; // Herzschlag oder Bruchstück
      }

      switch (event['type']) {
        case 'content_block_delta':
          final delta = event['delta'] as Map<String, dynamic>?;
          switch (delta?['type']) {
            case 'text_delta':
              json.write(delta!['text'] as String? ?? '');
              yield PlanWriting(json.length);
            case 'thinking_delta':
              thinking += delta!['thinking'] as String? ?? '';
              yield PlanThinking(_lastSentence(thinking));
          }
        case 'message_delta':
          stopReason =
              (event['delta'] as Map<String, dynamic>?)?['stop_reason']
                  as String?;
        case 'error':
          throw PlanException(
            (event['error'] as Map<String, dynamic>?)?['message'] as String? ??
                'Die API meldete einen Fehler.',
          );
      }
    }

    // Vor dem Inhalt prüfen: bei einer Ablehnung ist die Antwort leer, und
    // "ungültiges JSON" wäre die falsche Erklärung dafür.
    if (stopReason == 'refusal') {
      throw const PlanException(
        'Die Anfrage wurde abgelehnt. Formulier sie anders oder wähle ein '
        'anderes Thema.',
      );
    }
    if (stopReason == 'max_tokens') {
      throw const PlanException(
        'Die Antwort war zu lang und wurde abgeschnitten. Bitte um einen '
        'kürzeren Plan (weniger Wochen oder Phasen).',
      );
    }

    final text = json.toString().trim();
    if (text.isEmpty) {
      throw const PlanException('Es kam kein Plan zurück.');
    }

    yield PlanDone(_parseBundle(text));
  }

  /// Trotz Anweisung kommt gelegentlich ein Code-Zaun oder ein einleitender
  /// Satz mit. Statt daran zu scheitern: das JSON-Objekt herausschneiden.
  static Bundle _parseBundle(String text) {
    var body = text;
    if (body.startsWith('```')) {
      final firstBreak = body.indexOf('\n');
      if (firstBreak != -1) body = body.substring(firstBreak + 1);
      final closing = body.lastIndexOf('```');
      if (closing != -1) body = body.substring(0, closing);
    }
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start == -1 || end <= start) {
      throw const PlanException('Die Antwort enthielt kein JSON-Objekt.');
    }

    final Bundle bundle;
    try {
      final decoded = jsonDecode(body.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) {
        throw const PlanException('Die Antwort war kein JSON-Objekt.');
      }
      bundle = Bundle.fromJson(decoded);
    } on PlanException {
      rethrow;
    } on FormatException catch (e) {
      throw PlanException('Ungültiges JSON: ${e.message}');
    } catch (e) {
      throw PlanException('Der Plan ließ sich nicht lesen: $e');
    }

    // Der Server weist Themenfremdes mit einem leeren Bundle ab — das ist
    // kein Formatfehler, sondern eine Ablehnung, und wird auch so gemeldet.
    if (bundle.programs.isEmpty) {
      throw const PlanException(
        'Daraus ließ sich kein Übungsplan machen. Beschreib eine Fähigkeit, '
        'die du üben willst.',
      );
    }
    return bundle;
  }

  static String _lastSentence(String thinking) {
    final trimmed = thinking.trimRight();
    if (trimmed.isEmpty) return '';
    final cut = trimmed.lastIndexOf(RegExp(r'[.!?]\s'));
    final tail = cut == -1 ? trimmed : trimmed.substring(cut + 1);
    return tail.trim();
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
