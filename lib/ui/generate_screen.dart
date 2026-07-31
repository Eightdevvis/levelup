import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/plan_service.dart';
import '../main.dart';
import '../model/library.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Plan direkt in der App erzeugen lassen.
///
/// Es gibt keine Anmeldung und keinen Schlüssel: das Gerät meldet sich beim
/// ersten Öffnen einmalig bei der LevelUp-API an und behält sein Token. Der
/// Weg über Kopieren und Einfügen bleibt daneben bestehen — er kostet nichts
/// und braucht überhaupt keinen Server.
class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key, this.serviceFactory, this.registrar});

  /// Nur für Tests: einen Dienst mit vorgegebenen Antworten einsetzen.
  final PlanService Function(String token)? serviceFactory;

  /// Nur für Tests: die Geräteanmeldung ersetzen.
  final Future<String> Function()? registrar;

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final _request = TextEditingController();
  StreamSubscription<PlanEvent>? _run;

  String? _thinking;
  int _chars = 0;
  String? _error;
  Quota? _quota;
  bool _connecting = true;
  String? _connectError;

  bool get _running => _run != null;

  @override
  void initState() {
    super.initState();
    // Erst nach dem ersten Frame: vorher gibt es kein AppScope im Kontext.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _run?.cancel();
    _request.dispose();
    super.dispose();
  }

  PlanService _service(String token) =>
      (widget.serviceFactory ??
          (t) => PlanService(baseUrl: PlanService.defaultBaseUrl, token: t))(
        token,
      );

  /// Gerät anmelden (falls nötig) und das Kontingent holen.
  Future<void> _connect() async {
    if (!mounted) return;
    final state = AppScope.of(context);
    setState(() {
      _connecting = true;
      _connectError = null;
    });

    try {
      var token = state.deviceToken;
      if (token == null) {
        token = await (widget.registrar ?? _register)();
        await state.setDeviceToken(token);
      }
      final quota = await _service(token).quota();
      if (!mounted) return;
      setState(() {
        _quota = quota;
        _connecting = false;
      });
    } on PlanException catch (e) {
      if (!mounted) return;
      setState(() {
        _connectError = e.message;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectError = 'Verbindung fehlgeschlagen: $e';
        _connecting = false;
      });
    }
  }

  static Future<String> _register() => PlanService.register(
    baseUrl: PlanService.defaultBaseUrl,
    platform: defaultTargetPlatform.name,
  );

  Future<void> _start() async {
    final state = AppScope.of(context);
    final token = state.deviceToken;
    if (token == null) {
      await _connect();
      return;
    }

    setState(() {
      _error = null;
      _thinking = null;
      _chars = 0;
    });

    final sub = _service(token)
        .generatePlan(_request.text)
        .listen(
          (event) {
            if (!mounted) return;
            switch (event) {
              case PlanThinking(:final text):
                setState(() => _thinking = text);
              case PlanWriting(:final chars):
                setState(() => _chars = chars);
              case PlanDone(:final bundle):
                _install(bundle);
            }
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _error = '$e';
              _run = null;
            });
          },
          onDone: () {
            if (mounted) setState(() => _run = null);
          },
          cancelOnError: true,
        );

    setState(() => _run = sub);
  }

  Future<void> _install(Bundle bundle) async {
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await state.installBundle(bundle);
    if (!mounted) return;

    // Ein Lauf ist verbraucht — den Zählerstand vom Server holen, statt ihn
    // hier zu raten.
    unawaited(_refreshQuota());

    final program = bundle.programs.isEmpty ? null : bundle.programs.first;
    messenger.showSnackBar(const SnackBar(content: Text('// PLAN ERZEUGT')));
    if (program == null) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramScreen(programId: program.id),
      ),
    );
  }

  Future<void> _refreshQuota() async {
    final token = AppScope.of(context).deviceToken;
    if (token == null) return;
    try {
      final quota = await _service(token).quota();
      if (mounted) setState(() => _quota = quota);
    } on Exception {
      // Der Zählerstand ist Beiwerk; ein Fehler hier darf nichts kippen.
    }
  }

  void _cancel() {
    _run?.cancel();
    setState(() => _run = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    if (_connecting) {
      return Scaffold(
        appBar: AppBar(title: const Text('PLAN ERZEUGEN')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_connectError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PLAN ERZEUGEN')),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'nicht verbunden',
          message: _connectError!,
          action: OutlinedButton(
            onPressed: _connect,
            child: const Text('NOCHMAL VERSUCHEN'),
          ),
        ),
      );
    }

    final quota = _quota;
    final exhausted = quota != null && quota.exhausted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PLAN ERZEUGEN'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 40),
        children: [
          Text(
            'Beschreib, was du erreichen willst und wo es klemmt. Je genauer '
            'das Problem, desto besser die Diagnose — der Plan stellt auf die '
            'Ursache ab, nicht auf das Symptom.',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 11,
              height: 1.65,
              color: p.fgDim,
            ),
          ),
          const SectionLabel('dein anliegen'),
          TextField(
            controller: _request,
            minLines: 5,
            maxLines: 12,
            enabled: !_running && !exhausted,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 11.5,
              height: 1.6,
              color: p.fg,
            ),
            decoration: const InputDecoration(
              hintText:
                  'Ich spiele gut Geige, kann aber Bach nicht vom Blatt '
                  'lesen. Zwölf Wochen, etwa 45 Minuten am Tag.',
            ),
          ),
          const SizedBox(height: 14),
          if (_running)
            OutlinedButton(onPressed: _cancel, child: const Text('ABBRECHEN'))
          else
            FilledButton(
              onPressed: exhausted ? null : _start,
              child: const Text('PLAN ERZEUGEN'),
            ),
          if (_running || _thinking != null || _error != null) ...[
            const SectionLabel('verlauf'),
            _Progress(
              running: _running,
              thinking: _thinking,
              chars: _chars,
              error: _error,
            ),
          ],
          const SectionLabel('kontingent'),
          _QuotaBox(quota: quota),
        ],
      ),
    );
  }
}

class _QuotaBox extends StatelessWidget {
  const _QuotaBox({required this.quota});

  final Quota? quota;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final q = quota;

    final message = q == null
        ? 'Der Zählerstand ist gerade nicht bekannt.'
        : q.exhausted
        ? 'Dein Freikontingent ist aufgebraucht. Der Weg über Prompt kopieren '
              'und JSON einfügen bleibt offen und kostet nichts.'
        : 'Noch ${q.remaining} ${q.remaining == 1 ? "Plan" : "Pläne"} frei, '
              'davon heute ${q.dailyRemaining}. Bisher erzeugt: ${q.used}. '
              'Abgerechnet wird nur, was auch ankommt — ein abgebrochener '
              'Lauf zählt nicht.';

    return ZBox(
      title: 'kontingent',
      trailing: q == null ? null : '${q.remaining} FREI',
      accent: q != null && q.exhausted ? p.error : p.accent,
      filled: false,
      child: Text(
        message,
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 10.5,
          height: 1.65,
          color: p.fgDim,
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.running,
    required this.thinking,
    required this.chars,
    required this.error,
  });

  final bool running;
  final String? thinking;
  final int chars;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final failed = error != null;

    return ZBox(
      title: failed
          ? 'fehlgeschlagen'
          : running
          ? (chars > 0 ? 'schreibt' : 'denkt')
          : 'fertig',
      accent: failed ? p.error : p.accent,
      filled: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed)
            Text(
              error!,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 11,
                height: 1.6,
                color: p.error,
              ),
            )
          else ...[
            if (thinking != null && thinking!.isNotEmpty)
              Text(
                thinking!,
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                  color: p.fgDim,
                ),
              ),
            if (chars > 0) ...[
              if (thinking != null) const SizedBox(height: 10),
              Text(
                '$chars ZEICHEN PLAN',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 9.5,
                  letterSpacing: 1.3,
                  color: p.fgFaint,
                ),
              ),
            ],
          ],
          if (running) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}
