// Erzeugt den Katalog der offenen Bibliothek unter `library/`.
//
//   dart run tool/build_library.dart
//
// Quelle sind die Programme aus `lib/data/seed.dart`. Wer einen Plan
// beisteuern will, legt ihn dort ab (oder exportiert ihn aus der App und legt
// die JSON-Datei direkt nach `library/`) und lässt das hier neu laufen — der
// Index wird aus den Bundles berechnet, nicht von Hand gepflegt, damit
// Wochenzahl und Übungsanzahl nicht auseinanderlaufen.

import 'dart:convert';
import 'dart:io';

import 'package:programs/data/seed.dart';
import 'package:programs/model/library.dart';

void main() {
  final library = const Library().merge(seedBundle());
  final dir = Directory('library')..createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');

  final index = <Map<String, dynamic>>[];

  final programs = library.programs.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  for (final program in programs) {
    final bundle = library.bundleForProgram(program.id);
    final file = '${program.id}.json';

    File(
      '${dir.path}/$file',
    ).writeAsStringSync('${encoder.convert(bundle.toJson())}\n');

    index.add({
      'id': program.id,
      'name': program.name,
      'file': file,
      'domain': program.domain,
      if (program.description != null) 'description': program.description,
      if (program.author != null) 'author': program.author,
      'weeks': program.totalWeeks,
      'phases': program.phases.length,
      'exercises': bundle.exercises.length,
      if (program.tags.isNotEmpty) 'tags': program.tags,
    });

    stdout.writeln(
      '  $file — ${program.name} '
      '(${program.totalWeeks} Wochen, ${bundle.exercises.length} Übungen)',
    );
  }

  File('${dir.path}/index.json').writeAsStringSync(
    '${encoder.convert({'version': kBundleVersion, 'programs': index})}\n',
  );

  stdout.writeln('  index.json — ${index.length} Programme');
}
