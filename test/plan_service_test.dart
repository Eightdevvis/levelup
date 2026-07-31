import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:programs/data/plan_service.dart';
import 'package:programs/model/library.dart';

/// Ein kleines, aber vollständiges Bundle — genug, damit `Bundle.fromJson`
/// etwas Echtes zu tun hat.
const _bundleJson = '''
{
  "version": 1,
  "exercises": [{
    "id": "rhythmus-klopfen",
    "name": "Rhythmus klopfen",
    "domain": "geige",
    "summary": "Takt ohne Instrument fühlen.",
    "instructions": ["Metronom an", "Takt mitklopfen"],
    "benefits": ["Sicherheit im Puls"],
    "defaultSets": [{"target": {"kind": "duration", "seconds": 300}}]
  }],
  "routines": [{
    "id": "tag-a",
    "name": "Tag A",
    "slots": [{
      "exerciseId": "rhythmus-klopfen",
      "sets": [{"target": {"kind": "duration", "seconds": 300}}]
    }]
  }],
  "programs": [{
    "id": "bach-lesen",
    "name": "Bach lesen",
    "description": "Notation vor Repertoire.",
    "domain": "geige",
    "rationale": "Das Problem ist die Notation, nicht die Technik.",
    "phases": [{
      "id": "grundlage",
      "name": "Grundlage",
      "weeks": 4,
      "schedule": {"kind": "everyDay", "routineId": "tag-a", "daysPerWeek": 6}
    }]
  }]
}
''';

/// Baut einen SSE-Strom, wie ihn der Worker durchreicht.
String _sse({
  required String text,
  String? thinking,
  String stopReason = 'end_turn',
}) {
  final lines = <String>[
    'event: message_start',
    'data: ${jsonEncode({
      "type": "message_start",
      "message": {"id": "msg_1"},
    })}',
    '',
  ];

  if (thinking != null) {
    lines.addAll([
      'data: ${jsonEncode({
        "type": "content_block_delta",
        "index": 0,
        "delta": {"type": "thinking_delta", "thinking": thinking},
      })}',
      '',
    ]);
  }

  // Bewusst in Häppchen, damit das Zusammensetzen mitgetestet wird.
  for (var i = 0; i < text.length; i += 64) {
    final chunk = text.substring(i, (i + 64).clamp(0, text.length));
    lines.addAll([
      'data: ${jsonEncode({
        "type": "content_block_delta",
        "index": 0,
        "delta": {"type": "text_delta", "text": chunk},
      })}',
      '',
    ]);
  }

  lines.addAll([
    'data: ${jsonEncode({
      "type": "message_delta",
      "delta": {"stop_reason": stopReason},
      "usage": {"output_tokens": 1200},
    })}',
    '',
    'data: [DONE]',
    '',
  ]);
  return lines.join('\n');
}

/// Antwortet auf `/v1/generate` mit einem Strom, auf alles andere mit 404.
MockClient _streaming(String body, {int status = 200}) =>
    MockClient.streaming((request, _) async {
      expect(request.headers['authorization'], 'Bearer tok_test');
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        status,
        request: request,
        headers: {'content-type': 'text/event-stream'},
      );
    });

Future<Bundle> _run(PlanService service, [String request = 'Bach lesen']) async {
  final events = await service.generatePlan(request).toList();
  return (events.last as PlanDone).bundle;
}

void main() {
  group('register', () {
    test('liefert das Token und merkt sich die Plattform', () async {
      String? sentPlatform;
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/devices');
        sentPlatform =
            (jsonDecode(request.body) as Map<String, dynamic>)['platform']
                as String?;
        return http.Response(
          jsonEncode({
            'deviceId': 'dev_1',
            'token': 'tok_neu',
            'freeGenerations': 3,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final token = await PlanService.register(
        baseUrl: 'https://api.test',
        platform: 'android',
        client: client,
      );

      expect(token, 'tok_neu');
      expect(sentPlatform, 'android');
    });

    test('meldet einen Serverfehler in Klartext', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Gerade zu viel los.', 'code': 'busy'},
          }),
          503,
        ),
      );

      expect(
        () => PlanService.register(
          baseUrl: 'https://api.test',
          platform: 'linux',
          client: client,
        ),
        throwsA(
          isA<PlanException>().having(
            (e) => e.message,
            'message',
            'Gerade zu viel los.',
          ),
        ),
      );
    });
  });

  group('quota', () {
    test('liest den Zählerstand', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'remaining': 2, 'dailyRemaining': 9, 'used': 1}),
          200,
        ),
      );
      final quota = await PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: client,
      ).quota();

      expect(quota.remaining, 2);
      expect(quota.dailyRemaining, 9);
      expect(quota.used, 1);
      expect(quota.exhausted, isFalse);
    });

    test('ein unbekanntes Gerät ist erklärbar, nicht nur ein Statuscode',
        () async {
      final client = MockClient((_) async => http.Response('nope', 401));
      expect(
        () => PlanService(
          baseUrl: 'https://api.test',
          token: 'tok_test',
          client: client,
        ).quota(),
        throwsA(
          isA<PlanException>().having(
            (e) => e.message,
            'message',
            contains('nicht angemeldet'),
          ),
        ),
      );
    });
  });

  group('generatePlan', () {
    test('setzt den Strom zu einem Bundle zusammen', () async {
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: _streaming(
          _sse(text: _bundleJson, thinking: 'Erst die Notation. Dann Bach.'),
        ),
      );

      final events = await service.generatePlan('Bach lesen').toList();

      expect(events.whereType<PlanThinking>(), isNotEmpty);
      expect(events.whereType<PlanWriting>(), isNotEmpty);

      final bundle = (events.last as PlanDone).bundle;
      expect(bundle.programs.single.id, 'bach-lesen');
      expect(bundle.exercises.single.name, 'Rhythmus klopfen');
      expect(bundle.routines.single.slots.single.exerciseId, 'rhythmus-klopfen');
    });

    test('meldet den letzten Gedanken, nicht den ganzen Gedankengang',
        () async {
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: _streaming(
          _sse(
            text: _bundleJson,
            thinking: 'Zuerst prüfe ich das Ziel. Die Notation ist die Lücke.',
          ),
        ),
      );

      final events = await service.generatePlan('Bach lesen').toList();
      final thoughts = events.whereType<PlanThinking>().toList();

      expect(thoughts.last.text, 'Die Notation ist die Lücke.');
    });

    test('schneidet einen Code-Zaun heraus', () async {
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: _streaming(_sse(text: '```json\n$_bundleJson\n```')),
      );

      expect((await _run(service)).programs.single.id, 'bach-lesen');
    });

    test('eine Ablehnung ist eine Ablehnung, kein Formatfehler', () async {
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: _streaming(_sse(text: '', stopReason: 'refusal')),
      );

      expect(
        () => _run(service),
        throwsA(
          isA<PlanException>().having(
            (e) => e.message,
            'message',
            contains('abgelehnt'),
          ),
        ),
      );
    });

    test('abgeschnittene Antworten sagen, was zu tun ist', () async {
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: _streaming(
          _sse(text: '{"version":1,"programs":[', stopReason: 'max_tokens'),
        ),
      );

      expect(
        () => _run(service),
        throwsA(
          isA<PlanException>().having(
            (e) => e.message,
            'message',
            contains('kürzeren Plan'),
          ),
        ),
      );
    });

    test('ein leeres Bundle ist die Absage des Servers an Themenfremdes',
        () async {
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: _streaming(
          _sse(
            text: '{"version":1,"exercises":[],"routines":[],"programs":[]}',
          ),
        ),
      );

      expect(
        () => _run(service),
        throwsA(
          isA<PlanException>().having(
            (e) => e.message,
            'message',
            contains('Beschreib eine Fähigkeit'),
          ),
        ),
      );
    });

    test('aufgebrauchtes Kontingent ist am Code erkennbar', () async {
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: _streaming(
          jsonEncode({
            'error': {
              'message': 'Dein Freikontingent ist aufgebraucht.',
              'code': 'quota_exhausted',
            },
          }),
          status: 402,
        ),
      );

      expect(
        () => _run(service),
        throwsA(
          isA<PlanException>()
              .having((e) => e.quotaExhausted, 'quotaExhausted', isTrue)
              .having((e) => e.message, 'message', contains('aufgebraucht')),
        ),
      );
    });

    test('das Tageslimit zählt auch als aufgebraucht', () async {
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: _streaming(
          jsonEncode({
            'error': {'message': 'Genug für heute.', 'code': 'daily_limit'},
          }),
          status: 429,
        ),
      );

      expect(
        () => _run(service),
        throwsA(
          isA<PlanException>().having(
            (e) => e.quotaExhausted,
            'quotaExhausted',
            isTrue,
          ),
        ),
      );
    });

    test('eine leere Anfrage geht gar nicht erst raus', () async {
      var called = false;
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: MockClient.streaming((request, _) async {
          called = true;
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
      );

      await expectLater(
        service.generatePlan('   ').toList(),
        throwsA(isA<PlanException>()),
      );
      expect(called, isFalse);
    });

    test('Bruchstücke im Strom kippen den Lauf nicht', () async {
      final withNoise = _sse(text: _bundleJson)
          .replaceFirst('\n\n', '\n: keep-alive\ndata: {kaputt\n\n');
      final service = PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: _streaming(withNoise),
      );

      expect((await _run(service)).programs.single.id, 'bach-lesen');
    });
  });
}
