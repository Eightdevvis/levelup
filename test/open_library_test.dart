import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:programs/data/open_library.dart';
import 'support/seed.dart';
import 'package:programs/data/storage.dart';
import 'package:programs/model/library.dart';
import 'package:programs/state/app_state.dart';

/// Antwortet mit vorgegebenen Inhalten, damit die Tests ohne Netz laufen.
///
/// Geschlüsselt wird über das letzte Adressteil: `library` ist der Katalog
/// selbst, alles andere ein einzelner Plan — entweder über seine Kennung oder,
/// bei einem alten Katalog aus Dateien, über den Dateinamen.
OpenLibraryClient _clientWith(Map<String, String> routes, {int status = 200}) {
  final mock = MockClient((request) async {
    final body = routes[request.url.path.split('/').last];
    if (body == null) return http.Response('nicht da', 404);
    return http.Response.bytes(utf8.encode(body), status);
  });
  return OpenLibraryClient(client: mock, base: 'https://example.test/library');
}

const _index = '''
{
  "version": 1,
  "programs": [
    {
      "id": "p-test",
      "name": "Testprogramm",
      "file": "p-test.json",
      "domain": "test",
      "description": "Ein Plan zum Prüfen.",
      "author": "Sasha",
      "weeks": 4,
      "phases": 1,
      "exercises": 2,
      "tags": ["probe"]
    }
  ]
}
''';

/// Wie der Server ihn liefert: keine Dateinamen, adressiert wird über die id.
const _poolIndex = '''
{
  "version": 1,
  "programs": [
    {
      "id": "geige-blattlesen",
      "name": "Blattlesen",
      "domain": "geige",
      "description": "Aus dem Pool.",
      "weeks": 6,
      "phases": 2,
      "exercises": 5
    }
  ]
}
''';

void main() {
  group('Pool als Katalog', () {
    test('ein Eintrag ohne Dateinamen wird über die Kennung geholt', () async {
      final client = _clientWith({
        'library': _poolIndex,
        'geige-blattlesen': jsonEncode(seedBundle().toJson()),
      });

      final entries = await client.fetchCatalog();
      expect(entries.single.file, isEmpty);
      expect(entries.single.name, 'Blattlesen');

      // Ohne Dateifeld muss der Client die Kennung anhängen — täte er es
      // nicht, liefe die Anfrage ins Leere und niemand bekäme je einen Plan
      // aus dem Pool.
      final bundle = await client.fetchBundle(entries.single);
      expect(bundle.programs, isNotEmpty);
    });
  });

  group('Katalog', () {
    test('liest die Einträge', () async {
      final client = _clientWith({'library': _index});
      final entries = await client.fetchCatalog();

      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.id, 'p-test');
      expect(entry.name, 'Testprogramm');
      expect(entry.weeks, 4);
      expect(entry.exercises, 2);
      expect(entry.author, 'Sasha');
      expect(entry.tags, ['probe']);
    });

    test('nimmt auch eine nackte Liste an', () async {
      final bare = jsonEncode([
        {'id': 'x', 'name': 'X', 'file': 'x.json'},
      ]);
      final entries = await _clientWith({'library': bare}).fetchCatalog();
      expect(entries.single.id, 'x');
      // Fehlende Angaben dürfen nicht werfen, sondern fallen auf Vorgaben.
      expect(entries.single.domain, 'allgemein');
      expect(entries.single.weeks, 0);
    });

    test('meldet 404 verständlich', () async {
      final client = _clientWith(const {});
      expect(
        () => client.fetchCatalog(),
        throwsA(
          isA<OpenLibraryException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test('Umlaute überleben eine Antwort ohne charset', () async {
      final withUmlauts = jsonEncode([
        {'id': 'g', 'name': 'Gehörtraining für Anfänger', 'file': 'g.json'},
      ]);
      final entries = await _clientWith({
        'library': withUmlauts,
      }).fetchCatalog();
      expect(entries.single.name, 'Gehörtraining für Anfänger');
    });
  });

  group('Programm holen', () {
    test('liefert ein vollständiges Bundle', () async {
      final bundle = const Library()
          .merge(seedBundle())
          .bundleForProgram('p-gehoer');

      final client = _clientWith({
        'library': _index,
        'p-test.json': jsonEncode(bundle.toJson()),
      });

      final entry = (await client.fetchCatalog()).single;
      final fetched = await client.fetchBundle(entry);

      expect(fetched.programs.single.id, 'p-gehoer');
      expect(fetched.exercises, isNotEmpty);
      expect(fetched.routines, isNotEmpty);
    });

    test('meldet kaputtes JSON, statt zu werfen wie es will', () async {
      final client = _clientWith({'library': _index, 'p-test.json': '[]'});
      final entry = (await client.fetchCatalog()).single;

      expect(
        () => client.fetchBundle(entry),
        throwsA(isA<OpenLibraryException>()),
      );
    });
  });

  group('Installieren', () {
    test('legt das Bundle in die Bibliothek und bleibt erhalten', () async {
      final backend = MemoryStorageBackend();
      final state = AppState(Store(backend));
      await state.init();
      expect(state.programs, isEmpty);

      final bundle = const Library()
          .merge(seedBundle())
          .bundleForProgram('p-kraft-basis');
      await state.installBundle(bundle);

      expect(state.library.program('p-kraft-basis'), isNotNull);
      expect(state.library.missingReferences('p-kraft-basis'), isEmpty);

      final reloaded = AppState(Store(backend));
      await reloaded.init();
      expect(reloaded.library.program('p-kraft-basis'), isNotNull);
    });
  });
}
