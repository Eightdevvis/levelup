import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:programs/data/plan_service.dart';
import 'package:programs/model/library.dart';

/// Ein kleines, aber vollständiges Bundle.
const _bundle = {
  'version': 1,
  'personalNote': 'Dein eigentliches Problem ist die Notation, nicht Bach.',
  'exercises': [
    {
      'id': 'geige-rhythmus-klopfen',
      'name': 'Rhythmus klopfen',
      'domain': 'geige',
      'summary': 'Takt ohne Instrument fühlen.',
      'instructions': ['Metronom an', 'Takt mitklopfen'],
      'benefits': ['Sicherheit im Puls'],
      'defaultSets': [
        {
          'target': {'kind': 'duration', 'seconds': 300},
        },
      ],
    },
  ],
  'routines': [
    {
      'id': 'tag-a',
      'name': 'Tag A',
      'slots': [
        {
          'exerciseId': 'geige-rhythmus-klopfen',
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
      'id': 'bach-lesen',
      'name': 'Bach lesen',
      'description': 'Notation vor Repertoire.',
      'domain': 'geige',
      'rationale': 'Wer Barock vom Blatt spielt, braucht die Taktstruktur.',
      'phases': [
        {
          'id': 'grundlage',
          'name': 'Grundlage',
          'weeks': 4,
          'schedule': {
            'kind': 'everyDay',
            'routineId': 'tag-a',
            'daysPerWeek': 6,
          },
        },
      ],
    },
  ],
};

/// Der Server schickt sein eigenes Protokoll — kein Anthropic-Rohformat mehr.
String _sse(List<Map<String, dynamic>> events) =>
    events.map((e) => 'data: ${jsonEncode(e)}\n').join('\n');

PlanService _service(
  String body, {
  int status = 200,
  void Function(String path, Map<String, dynamic> body)? onRequest,
}) => PlanService(
  baseUrl: 'https://api.test',
  token: 'tok_test',
  client: MockClient.streaming((request, bodyStream) async {
    expect(request.headers['authorization'], 'Bearer tok_test');
    if (onRequest != null) {
      final raw = await bodyStream.bytesToString();
      onRequest(request.url.path, jsonDecode(raw) as Map<String, dynamic>);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }),
);

Future<List<PlanEvent>> _events(Stream<PlanEvent> stream) => stream.toList();

void main() {
  group('register', () {
    test('liefert das Token und meldet die Plattform', () async {
      String? platform;
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/devices');
        platform =
            (jsonDecode(request.body) as Map<String, dynamic>)['platform']
                as String?;
        return http.Response(
          jsonEncode({'deviceId': 'dev_1', 'token': 'tok_neu'}),
          200,
        );
      });

      final token = await PlanService.register(
        baseUrl: 'https://api.test',
        platform: 'android',
        client: client,
      );

      expect(token, 'tok_neu');
      expect(platform, 'android');
    });

    test('meldet einen Serverfehler in Klartext', () {
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
        (_) async => http.Response(
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

    test('ein unbekanntes Gerät ist erklärbar, nicht nur ein Statuscode', () {
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

  group('erzeugePlan', () {
    test('meldet Denken, Suchen, Schreiben und liefert den Plan', () async {
      final events = await _events(
        _service(
          _sse([
            {'type': 'thinking', 'text': 'Die Notation ist die Lücke.'},
            {
              'type': 'search',
              'tool': 'uebungen',
              'terms': ['notation'],
              'hits': 3,
            },
            {'type': 'writing', 'chars': 400},
            {
              'type': 'done',
              'bundle': _bundle,
              'kennzahlen': {'bedarfe': 4, 'reuse': 1, 'neu': 3},
            },
          ]),
        ).erzeugePlan('lauf_1'),
      );

      expect(events.whereType<PlanThinking>().single.text,
          'Die Notation ist die Lücke.');
      expect(events.whereType<PlanWriting>().single.chars, 400);

      final suche = events.whereType<PlanSearching>().single;
      expect(suche.hits, 3);
      expect(suche.describe(), contains('3'));

      final done = events.whereType<PlanDone>().single;
      expect(done.bundle.programs.single.id, 'bach-lesen');
      expect(done.uebernommen, 1);
      expect(
        done.bundle.personalNote,
        'Dein eigentliches Problem ist die Notation, nicht Bach.',
      );
    });

    test('eine Suche ohne Treffer wird auch so gesagt', () async {
      final events = await _events(
        _service(
          _sse([
            {
              'type': 'search',
              'tool': 'plaene',
              'terms': ['zehnfinger'],
              'hits': 0,
            },
            {'type': 'done', 'bundle': _bundle},
          ]),
        ).erzeugePlan('lauf_1'),
      );

      expect(
        events.whereType<PlanSearching>().single.describe(),
        contains('selbst gebaut'),
      );
    });

    test('ein Fehlerereignis wird zur Ausnahme mit Code', () {
      expect(
        () => _events(
          _service(
            _sse([
              {
                'type': 'error',
                'code': 'not_a_plan',
                'message': 'Daraus wird kein Übungsplan.',
              },
            ]),
          ).erzeugePlan('lauf_1'),
        ),
        throwsA(
          isA<PlanException>()
              .having((e) => e.code, 'code', 'not_a_plan')
              .having((e) => e.message, 'message', contains('kein Übungsplan')),
        ),
      );
    });

    test('aufgebrauchtes Kontingent ist am Code erkennbar', () {
      expect(
        () => _events(
          _service(
            jsonEncode({
              'error': {
                'message': 'Freikontingent aufgebraucht.',
                'code': 'quota_exhausted',
              },
            }),
            status: 402,
          ).erzeugePlan('lauf_1'),
        ),
        throwsA(
          isA<PlanException>().having(
            (e) => e.quotaExhausted,
            'quotaExhausted',
            isTrue,
          ),
        ),
      );
    });

    test('ein Strom ohne Ergebnis ist ein Abriss, kein stiller Erfolg', () {
      expect(
        () => _events(
          _service(
            _sse([
              {'type': 'thinking', 'text': 'Ich überlege...'},
            ]),
          ).erzeugePlan('lauf_1'),
        ),
        throwsA(
          isA<PlanException>().having(
            (e) => e.message,
            'message',
            contains('brach ab'),
          ),
        ),
      );
    });

    test('ein leeres Vorhaben geht gar nicht erst raus', () async {
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
        service.starteLauf(
          const Eingabe(
            vorhaben: '   ',
            stand: '',
            minutenProTag: 30,
            tageProWoche: 4,
            equipment: '',
          ),
        ),
        throwsA(isA<PlanException>()),
      );
      expect(called, isFalse);
    });

    test('meldet den Schritt, damit der Balken sich bewegt', () async {
      final events = await _events(
        _service(
          _sse([
            {'type': 'schritt', 'name': 'kurator', 'fertig': 2, 'gesamt': 5},
            {'type': 'done', 'bundle': _bundle},
          ]),
        ).erzeugePlan('lauf_1'),
      );

      final schritt = events.whereType<PlanSchritt>().single;
      expect(schritt.describe(), contains('3/5'));
      expect(schritt.describe(), contains('Übungen ausfüllen'));
    });

    test('Bruchstücke im Strom kippen den Lauf nicht', () async {
      final noisy =
          'data: {kaputt\n\n: herzschlag\n\n'
          '${_sse([
            {'type': 'done', 'bundle': _bundle},
          ])}';

      final events = await _events(_service(noisy).erzeugePlan('lauf_1'));
      expect(events.whereType<PlanDone>().single.bundle.programs, hasLength(1));
    });
  });

  group('revisePlan', () {
    test('liefert Änderungen statt eines neuen Plans', () async {
      final events = await _events(
        _service(
          jsonEncode({
            'patch': {
              'personalNote': 'Die Fingerübung ist raus.',
              'operations': [
                {'op': 'removeExercise', 'exerciseId': 'geige-rhythmus-klopfen'},
              ],
            },
          }),
        ).revisePlan(Bundle.fromJson(Map.from(_bundle)), 'zu viel'),
      );

      final patch = events.whereType<PlanRevised>().single.patch;
      expect(patch.operations, hasLength(1));
      expect(patch.personalNote, 'Die Fingerübung ist raus.');
    });

    test('der persönliche Teil wird nicht mitgeschickt', () async {
      Map<String, dynamic>? sent;
      await _events(
        _service(
          jsonEncode({
            'patch': {'operations': <Map<String, dynamic>>[]},
          }),
          onRequest: (path, body) {
            expect(path, '/v1/revise');
            sent = body;
          },
        ).revisePlan(Bundle.fromJson(Map.from(_bundle)), 'zu viel'),
      );

      final bundle = sent?['bundle'] as Map<String, dynamic>?;
      expect(bundle, isNotNull);
      expect(bundle!.containsKey('personalNote'), isFalse);
      expect(sent?['feedback'], 'zu viel');
    });

    test('ohne Rückmeldung wird nichts verschickt', () async {
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
        service.revisePlan(Bundle.fromJson(Map.from(_bundle)), '  ').toList(),
        throwsA(isA<PlanException>()),
      );
      expect(called, isFalse);
    });
  });

  group('acceptPlan', () {
    test('schickt die teilbare Fassung, ohne den persönlichen Teil', () async {
      Map<String, dynamic>? sent;
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/plans/accept');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'ok': true, 'exercises': 1}), 200);
      });

      await PlanService(
        baseUrl: 'https://api.test',
        token: 'tok_test',
        client: client,
      ).acceptPlan(Bundle.fromJson(Map.from(_bundle)));

      final bundle = sent?['bundle'] as Map<String, dynamic>?;
      expect(bundle, isNotNull);
      // Der persönliche Teil verlässt das Gerät nicht. Der Server entfernt ihn
      // ebenfalls — aber worauf man sich verlässt, verschickt man nicht erst.
      expect(bundle!.containsKey('personalNote'), isFalse);
      expect((bundle['programs'] as List<dynamic>).single, isNotNull);
    });

    test('ein Fehler beim Teilen ist ein Fehler', () {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Zu groß.', 'code': 'bundle_too_large'},
          }),
          400,
        ),
      );

      expect(
        () => PlanService(
          baseUrl: 'https://api.test',
          token: 'tok_test',
          client: client,
        ).acceptPlan(Bundle.fromJson(Map.from(_bundle))),
        throwsA(
          isA<PlanException>().having((e) => e.code, 'code', 'bundle_too_large'),
        ),
      );
    });
  });
}
