import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:programs/data/claude_client.dart';

/// Baut eine SSE-Antwort aus einzelnen Ereignissen.
String _sse(List<Map<String, dynamic>> events) =>
    events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();

/// Client, der eine vorgegebene Antwort streamt, statt zu telefonieren.
/// [onRequest] bekommt den Rumpf, damit Tests prüfen können, was gesendet wurde.
ClaudeClient _clientWith(
  String body, {
  int status = 200,
  void Function(Map<String, dynamic> payload)? onRequest,
}) {
  final mock = _MockClient((request) async {
    onRequest?.call(jsonDecode(request.body) as Map<String, dynamic>);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': 'text/event-stream'},
    );
  });
  return ClaudeClient(apiKey: 'sk-test', client: mock);
}

class _MockClient extends http.BaseClient {
  _MockClient(this.handler);
  final Future<http.StreamedResponse> Function(http.Request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request as http.Request);
}

const _bundle = {
  'version': 1,
  'exercises': [
    {'id': 'x-1', 'name': 'Testübung', 'domain': 'test'},
  ],
  'routines': [
    {
      'id': 'x-r',
      'name': 'Testliste',
      'slots': [
        {
          'exerciseId': 'x-1',
          'sets': [
            {
              'target': {'kind': 'duration', 'seconds': 300},
            },
          ],
        },
      ],
    },
  ],
  'programs': [
    {
      'id': 'x-p',
      'name': 'Testprogramm',
      'domain': 'test',
      'phases': [
        {
          'id': 'ph',
          'name': 'Phase',
          'weeks': 4,
          'schedule': {
            'kind': 'everyDay',
            'routineId': 'x-r',
            'daysPerWeek': 7,
          },
        },
      ],
    },
  ],
};

/// Streamt einen Text in Häppchen, wie es die API täte.
List<Map<String, dynamic>> _textDeltas(String text, {int chunk = 40}) => [
  for (var i = 0; i < text.length; i += chunk)
    {
      'type': 'content_block_delta',
      'delta': {
        'type': 'text_delta',
        'text': text.substring(i, (i + chunk).clamp(0, text.length)),
      },
    },
];

void main() {
  group('Plan erzeugen', () {
    test('liest das Bundle aus dem Strom', () async {
      final client = _clientWith(
        _sse([
          {
            'type': 'message_start',
            'message': {
              'usage': {'input_tokens': 900, 'output_tokens': 0},
            },
          },
          {
            'type': 'content_block_delta',
            'delta': {
              'type': 'thinking_delta',
              'thinking': 'Erst die Ursache.',
            },
          },
          ..._textDeltas(jsonEncode(_bundle)),
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 4200},
          },
        ]),
      );

      final events = await client.generatePlan('Bach lesen lernen').toList();

      expect(events.whereType<PlanThinking>(), isNotEmpty);
      expect(events.whereType<PlanWriting>(), isNotEmpty);

      final done = events.whereType<PlanDone>().single;
      expect(done.bundle.programs.single.id, 'x-p');
      expect(done.bundle.exercises.single.id, 'x-1');
      expect(done.usage.outputTokens, 4200);
      expect(done.usage.inputTokens, 900);
    });

    test('sendet Modell, Schema und Anliegen', () async {
      Map<String, dynamic>? sent;
      final client = _clientWith(
        _sse([
          ..._textDeltas(jsonEncode(_bundle)),
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
          },
        ]),
        onRequest: (payload) => sent = payload,
      );

      await client.generatePlan('Mein Anliegen').toList();

      expect(sent!['model'], 'claude-opus-5');
      expect(sent!['stream'], isTrue);
      expect((sent!['thinking'] as Map)['type'], 'adaptive');
      final system = (sent!['system'] as List).single as Map<String, dynamic>;
      expect(system['text'], contains('"kind": "quota"'));
      // Das Schema ist bei jedem Aufruf gleich — es soll zwischengespeichert
      // werden, sonst zahlt man es jedes Mal neu.
      expect(system['cache_control'], isNotNull);
      final message =
          (sent!['messages'] as List).single as Map<String, dynamic>;
      expect(message['content'], 'Mein Anliegen');
    });

    test('verträgt einen Code-Zaun und Vorgeplänkel', () async {
      final client = _clientWith(
        _sse([
          ..._textDeltas(
            'Hier ist der Plan:\n```json\n${jsonEncode(_bundle)}\n```',
          ),
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
          },
        ]),
      );

      final done = (await client.generatePlan('x').toList())
          .whereType<PlanDone>()
          .single;
      expect(done.bundle.programs.single.name, 'Testprogramm');
    });
  });

  group('Fehler', () {
    Future<Object> caught(Stream<PlanEvent> stream) async {
      try {
        await stream.toList();
        fail('kein Fehler geworfen');
      } on Object catch (e) {
        return e;
      }
    }

    test('Ablehnung wird als solche gemeldet, nicht als JSON-Fehler', () async {
      final client = _clientWith(
        _sse([
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'refusal'},
          },
        ]),
      );
      expect(
        '${await caught(client.generatePlan('x'))}',
        contains('abgelehnt'),
      );
    });

    test('abgeschnittene Antwort nennt die Ursache', () async {
      final client = _clientWith(
        _sse([
          ..._textDeltas('{"version": 1, "programs": ['),
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'max_tokens'},
          },
        ]),
      );
      expect(
        '${await caught(client.generatePlan('x'))}',
        contains('abgeschnitten'),
      );
    });

    test('falscher Schlüssel wird erklärt, nicht durchgereicht', () async {
      final client = _clientWith(
        jsonEncode({
          'error': {'type': 'authentication_error', 'message': 'invalid'},
        }),
        status: 401,
      );
      expect(
        '${await caught(client.generatePlan('x'))}',
        contains('Schlüssel'),
      );
    });

    test('Überlastung wird erklärt', () async {
      final client = _clientWith('{}', status: 529);
      expect(
        '${await caught(client.generatePlan('x'))}',
        contains('überlastet'),
      );
    });

    test('kaputtes JSON meldet sich als solches', () async {
      final client = _clientWith(
        _sse([
          ..._textDeltas('{ das ist kein json '),
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
          },
        ]),
      );
      final error = '${await caught(client.generatePlan('x'))}';
      expect(error.toLowerCase(), contains('json'));
    });

    test('leere Eingabe wird gar nicht erst gesendet', () async {
      var called = false;
      final client = _clientWith('', onRequest: (_) => called = true);

      // generatePlan ist ein async*-Strom: die Prüfung greift beim Abonnieren,
      // nicht beim Aufruf — deshalb hier erst konsumieren.
      expect(await caught(client.generatePlan('   ')), isA<ClaudeException>());
      expect(called, isFalse, reason: 'darf keine Anfrage abgesetzt haben');
    });

    test('Fehlerereignis im Strom bricht sauber ab', () async {
      final client = _clientWith(
        _sse([
          {
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'zu viel los'},
          },
        ]),
      );
      expect('${await caught(client.generatePlan('x'))}', contains('zu viel'));
    });
  });

  group('Kosten', () {
    test('rechnet die Opus-5-Preise', () {
      // 1 Mio. Eingabe + 1 Mio. Ausgabe = 5 $ + 25 $
      const usage = PlanUsage(inputTokens: 1000000, outputTokens: 1000000);
      expect(usage.usd, closeTo(30, 0.001));
    });

    test('zwischengespeicherte Eingabe kostet ein Zehntel', () {
      const usage = PlanUsage(cacheReadTokens: 1000000);
      expect(usage.usd, closeTo(0.5, 0.001));
    });

    test('zeigt kleine Beträge in Cent', () {
      const usage = PlanUsage(outputTokens: 8000);
      expect(usage.describe(), contains('ct'));
    });
  });
}
