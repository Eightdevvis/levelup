import 'package:flutter/material.dart';

import '../data/open_library.dart';
import '../main.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Die offene Bibliothek: alle Programme, die je geteilt wurden.
///
/// Der Katalog liegt als Datei im Repo, nicht auf einem Server — es gibt
/// nichts zu betreiben, und ein neuer Plan kommt per Pull Request dazu.
class OpenLibraryScreen extends StatefulWidget {
  const OpenLibraryScreen({super.key, this.client});

  /// Nur für Tests: ein Client mit vorgegebenen Antworten.
  final OpenLibraryClient? client;

  @override
  State<OpenLibraryScreen> createState() => _OpenLibraryScreenState();
}

class _OpenLibraryScreenState extends State<OpenLibraryScreen> {
  late final OpenLibraryClient _client = widget.client ?? OpenLibraryClient();

  List<CatalogEntry>? _entries;
  String? _error;
  final Set<String> _installing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _entries = null;
    });
    try {
      final entries = await _client.fetchCatalog();
      if (!mounted) return;
      setState(() => _entries = entries);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _install(CatalogEntry entry) async {
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _installing.add(entry.id));

    try {
      final bundle = await _client.fetchBundle(entry);
      await state.installBundle(bundle);
      if (!mounted) return;
      setState(() => _installing.remove(entry.id));
      messenger.showSnackBar(
        SnackBar(content: Text('// ${entry.name.toUpperCase()} GELADEN')),
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProgramScreen(programId: entry.id),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _installing.remove(entry.id));
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final state = AppScope.of(context);
    final entries = _entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OFFENE BIBLIOTHEK'),
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            icon: Icon(Icons.refresh, color: p.fgDim),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.border),
        ),
      ),
      body: switch ((entries, _error)) {
        (_, final String error) => EmptyState(
          icon: Icons.cloud_off,
          title: 'nicht erreichbar',
          message: error,
          action: OutlinedButton(
            onPressed: _load,
            child: const Text('NOCHMAL VERSUCHEN'),
          ),
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final List<CatalogEntry> list, _) when list.isEmpty =>
          const EmptyState(
            icon: Icons.crop_square,
            title: 'noch leer',
            message: 'In der Bibliothek liegt bisher kein Programm.',
          ),
        (final List<CatalogEntry> list, _) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(15, 20, 15, 30),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 18),
          itemBuilder: (context, index) {
            final entry = list[index];
            return _CatalogBox(
              entry: entry,
              installed: state.library.program(entry.id) != null,
              busy: _installing.contains(entry.id),
              onInstall: () => _install(entry),
            );
          },
        ),
      },
      bottomNavigationBar: entries == null
          ? null
          : Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: p.border, width: Metrics.line),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 9, 15, 11),
                  child: Text(
                    '// ${entries.length} PROGRAMME IN DER BIBLIOTHEK',
                    style: TextStyle(
                      fontFamily: Metrics.mono,
                      fontSize: 8.5,
                      letterSpacing: 1.4,
                      color: p.fgFaint,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _CatalogBox extends StatelessWidget {
  const _CatalogBox({
    required this.entry,
    required this.installed,
    required this.busy,
    required this.onInstall,
  });

  final CatalogEntry entry;
  final bool installed;
  final bool busy;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    return ZBox(
      title: entry.domain,
      trailing: '${entry.weeks}W · ${entry.phases}PH',
      onTap: installed || busy ? null : onInstall,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.name,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: p.fg,
            ),
          ),
          if (entry.description != null) ...[
            const SizedBox(height: 8),
            Text(
              entry.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10.5,
                height: 1.6,
                color: p.fgDim,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${entry.exercises} ÜBUNGEN'
                  '${entry.author == null ? "" : " · ${entry.author!.toUpperCase()}"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 8.5,
                    letterSpacing: 1.3,
                    color: p.fgFaint,
                  ),
                ),
              ),
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: p.fgDim,
                  ),
                )
              else
                Text(
                  installed ? 'GELADEN' : '[ + LADEN ]',
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: installed ? p.fgFaint : p.accent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
