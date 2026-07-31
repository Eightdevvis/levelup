import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/library.dart';
import 'ai_prompt.dart';

/// Fortschritt einer laufenden Plan-Erzeugung.
///
/// Claude denkt bei einer Diagnose lange nach, bevor das erste Zeichen JSON
/// kommt. Ohne Zwischenmeldungen sähe die App eine Minute lang eingefroren aus,
/// deshalb wird der Verlauf als Strom gemeldet statt als einzelnes Ergebnis.
sealed class PlanEvent {
  const PlanEvent();
}

/// Claude überlegt. [text] ist die Zusammenfassung des Gedankengangs.
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
  const PlanDone(this.bundle, this.usage);
  final Bundle bundle;
  final PlanUsage usage;
}

/// Was der Aufruf gekostet hat — bei einem eigenen API-Schlüssel gehört das
/// sichtbar in die App und nicht in eine Abrechnung, die man erst später sieht.
class PlanUsage {
  const PlanUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;

  /// Preise für claude-opus-5: 5 $ je Mio. Eingabe, 25 $ je Mio. Ausgabe.
  /// Aus dem Cache gelesene Eingabe kostet ein Zehntel, geschriebene das
  /// 1,25-fache.
  double get usd =>
      inputTokens * 5 / 1000000 +
      outputTokens * 25 / 1000000 +
      cacheReadTokens * 0.5 / 1000000 +
      cacheWriteTokens * 6.25 / 1000000;

  String describe() {
    final cents = usd * 100;
    final price = cents < 100
        ? '${cents.toStringAsFixed(1)} ct'
        : '${usd.toStringAsFixed(2)} \$';
    return '$outputTokens Token · ~$price';
  }
}

/// Fehler, die dem Nutzer erklärbar sind.
class ClaudeException implements Exception {
  const ClaudeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Spricht mit der Claude-API.
///
/// Bewusst rohes HTTP: für Dart gibt es kein offizielles Anthropic-SDK, und
/// ein inoffizielles Paket für einen einzigen Endpunkt wäre mehr Abhängigkeit
/// als Nutzen.
class ClaudeClient {
  ClaudeClient({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  /// Das Modell. Claude Opus 5 denkt standardmäßig nach — genau das, was eine
  /// Diagnose braucht.
  static const model = 'claude-opus-5';

  /// Reichlich bemessen: `max_tokens` deckelt Denken UND Antwort zusammen, und
  /// ein Zwölf-Wochen-Plan mit allen Übungen ist allein schon umfangreich.
  static const maxTokens = 32000;

  Stream<PlanEvent> generatePlan(String request) async* {
    if (request.trim().isEmpty) {
      throw const ClaudeException('Beschreib erst, worum es gehen soll.');
    }

    final payload = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'stream': true,
      // Der Gedankengang als Zusammenfassung, damit die App zeigen kann, woran
      // Claude gerade arbeitet. Ohne dieses Feld bleiben die Blöcke leer.
      'thinking': {'type': 'adaptive', 'display': 'summarized'},
      // Das Schema ist bei jedem Aufruf identisch und lang genug, um zwischen-
      // gespeichert zu werden — der zweite Plan wird dadurch spürbar billiger.
      'system': [
        {
          'type': 'text',
          'text': kPlanSystemPrompt,
          'cache_control': {'type': 'ephemeral'},
        },
      ],
      'messages': [
        {'role': 'user', 'content': request},
      ],
    };

    final http.StreamedResponse response;
    try {
      final req = http.Request('POST', Uri.parse(_endpoint))
        ..headers.addAll({
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        })
        ..body = jsonEncode(payload);
      response = await _client.send(req);
    } on Exception catch (e) {
      throw ClaudeException('Kein Zugriff auf die Claude-API: $e');
    }

    if (response.statusCode != 200) {
      throw ClaudeException(await _describeError(response));
    }

    final json = StringBuffer();
    var usage = const PlanUsage();
    String? stopReason;
    var lastThinking = '';

    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final raw = line.substring(6);
      if (raw == '[DONE]') break;

      final Map<String, dynamic> event;
      try {
        event = jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException {
        continue; // Heartbeat oder Bruchstück — überspringen, nicht abbrechen.
      }

      switch (event['type']) {
        case 'message_start':
          usage = _mergeUsage(usage, event['message']?['usage']);
        case 'content_block_delta':
          final delta = event['delta'] as Map<String, dynamic>?;
          switch (delta?['type']) {
            case 'text_delta':
              json.write(delta!['text'] as String? ?? '');
              yield PlanWriting(json.length);
            case 'thinking_delta':
              lastThinking += delta!['thinking'] as String? ?? '';
              yield PlanThinking(_lastSentence(lastThinking));
          }
        case 'message_delta':
          stopReason =
              (event['delta'] as Map<String, dynamic>?)?['stop_reason']
                  as String?;
          usage = _mergeUsage(usage, event['usage']);
        case 'error':
          final message =
              (event['error'] as Map<String, dynamic>?)?['message'] as String?;
          throw ClaudeException(message ?? 'Die API meldete einen Fehler.');
      }
    }

    // Vor dem Inhalt prüfen: bei einer Ablehnung ist die Antwort leer oder
    // abgebrochen, und ein JSON-Fehler wäre die falsche Erklärung dafür.
    if (stopReason == 'refusal') {
      throw const ClaudeException(
        'Claude hat die Anfrage abgelehnt. Formulier sie anders '
        'oder wähle ein anderes Thema.',
      );
    }
    if (stopReason == 'max_tokens') {
      throw const ClaudeException(
        'Die Antwort war zu lang und wurde abgeschnitten. '
        'Bitte um einen kürzeren Plan (weniger Wochen oder Phasen).',
      );
    }

    final text = json.toString().trim();
    if (text.isEmpty) {
      throw const ClaudeException('Claude hat nichts zurückgegeben.');
    }

    yield PlanDone(_parseBundle(text), usage);
  }

  /// Claude antwortet trotz Anweisung gelegentlich mit einem Code-Zaun oder
  /// einem einleitenden Satz. Statt daran zu scheitern: das JSON-Objekt aus
  /// dem Text herausschneiden.
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
      throw const ClaudeException('Die Antwort enthielt kein JSON-Objekt.');
    }

    try {
      final decoded = jsonDecode(body.substring(start, end + 1));
      if (decoded is! Map<String, dynamic>) {
        throw const ClaudeException('Die Antwort war kein JSON-Objekt.');
      }
      return Bundle.fromJson(decoded);
    } on ClaudeException {
      rethrow;
    } on FormatException catch (e) {
      throw ClaudeException('Ungültiges JSON von Claude: ${e.message}');
    } catch (e) {
      throw ClaudeException('Der Plan ließ sich nicht lesen: $e');
    }
  }

  static PlanUsage _mergeUsage(PlanUsage current, Object? raw) {
    if (raw is! Map<String, dynamic>) return current;
    int read(String key, int fallback) =>
        (raw[key] as num?)?.round() ?? fallback;
    return PlanUsage(
      inputTokens: read('input_tokens', current.inputTokens),
      outputTokens: read('output_tokens', current.outputTokens),
      cacheReadTokens: read('cache_read_input_tokens', current.cacheReadTokens),
      cacheWriteTokens: read(
        'cache_creation_input_tokens',
        current.cacheWriteTokens,
      ),
    );
  }

  /// Nur der zuletzt begonnene Satz — der Gedankengang wird lang, und in der
  /// App ist eine Zeile Platz.
  static String _lastSentence(String thinking) {
    final trimmed = thinking.trimRight();
    if (trimmed.isEmpty) return '';
    final cut = trimmed.lastIndexOf(RegExp(r'[.!?]\s'));
    final tail = cut == -1 ? trimmed : trimmed.substring(cut + 1);
    return tail.trim();
  }

  Future<String> _describeError(http.StreamedResponse response) async {
    final body = await response.stream.bytesToString();
    String? detail;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        detail =
            (decoded['error'] as Map<String, dynamic>?)?['message'] as String?;
      }
    } on FormatException {
      // Kein JSON — dann eben nur der Status.
    }

    return switch (response.statusCode) {
      401 => 'Der API-Schlüssel wird nicht akzeptiert. Stimmt er noch?',
      403 => 'Dieser Schlüssel darf das Modell nicht benutzen.',
      429 => 'Zu viele Anfragen. Kurz warten und nochmal.',
      529 => 'Die API ist gerade überlastet. In ein paar Minuten nochmal.',
      _ => detail ?? 'Die API antwortete mit ${response.statusCode}.',
    };
  }

  void close() => _client.close();
}
