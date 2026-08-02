import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/plan_service.dart';
import '../main.dart';
import '../model/library.dart';
import '../model/patch.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Plan direkt in der App erzeugen lassen.
///
/// Der Ablauf hat bewusst einen Halt in der Mitte: der fertige Plan wird
/// vorgelegt, nicht eingebaut. Erst wer ihn annimmt, hat ihn in seiner
/// Bibliothek — und erst dann wandert er in die geteilte. Wer etwas anders
/// will, sagt es und bekommt eine Überarbeitung, die nur ändert, wovon die
/// Rede war.
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
  // Vier Felder statt einem (Spec §3). Das Equipment-Feld ist keine Zugabe:
  // ohne Angabe erzeugt die KI im Zweifel den kleinsten gemeinsamen Nenner.
  final _vorhaben = TextEditingController();
  final _stand = TextEditingController();
  final _equipment = TextEditingController();
  int _minutenProTag = 30;
  int _tageProWoche = 4;

  final _feedback = TextEditingController();
  StreamSubscription<PlanEvent>? _run;

  /// Der laufende Vorgang zwischen Diagnose und Plan.
  Diagnose? _diagnose;
  final _antworten = <TextEditingController>[];
  bool _diagnosing = false;

  /// Welcher Schritt der Pipeline gerade läuft.
  String? _schritt;

  String? _thinking;
  final _searches = <String>[];

  /// Der Gedankengang, wie er hereinkam.
  ///
  /// Er stand früher in voller Länge mitten im Ablauf — zwischen Plan und
  /// Knöpfen lagen dann leicht zweitausend Zeichen, durch die man scrollen
  /// musste, um etwas anzunehmen. Jetzt liegt er hinter einer Zeile.
  final _thoughts = <String>[];

  /// Ob das Feld für den Einspruch offen ist. Zu ist der Normalfall.
  bool _editing = false;
  int _chars = 0;
  String? _error;
  Quota? _quota;
  bool _connecting = true;
  String? _connectError;

  /// Der vorgelegte, noch nicht angenommene Plan.
  Bundle? _draft;
  int _uebernommen = 0;
  List<String> _skipped = const [];
  bool _accepting = false;

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
    _vorhaben.dispose();
    _stand.dispose();
    _equipment.dispose();
    for (final c in _antworten) {
      c.dispose();
    }
    _feedback.dispose();
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

  /// Hört einen Lauf ab — Erzeugen und Überarbeiten unterscheiden sich nur im
  /// Strom, den sie liefern.
  void _listen(Stream<PlanEvent> stream) {
    setState(() {
      _error = null;
      _thinking = null;
      _searches.clear();
      _thoughts.clear();
      _skipped = const [];
      _schritt = null;
      _chars = 0;
    });

    final sub = stream.listen(
      (event) {
        if (!mounted) return;
        switch (event) {
          case PlanThinking(:final text):
            setState(() {
              _thinking = text;
              // Der Server schickt jeweils den letzten Satz, der über mehrere
              // Ereignisse wächst. Ein Eintrag, der den vorigen fortsetzt,
              // ersetzt ihn, statt ihn zu wiederholen.
              if (text.trim().isEmpty) return;
              if (_thoughts.isNotEmpty &&
                  (text.startsWith(_thoughts.last) ||
                      _thoughts.last.startsWith(text))) {
                _thoughts[_thoughts.length - 1] = text;
              } else {
                _thoughts.add(text);
              }
            });
          case PlanWriting(:final chars):
            setState(() => _chars = chars);
          case PlanSearching():
            setState(() => _searches.add(event.describe()));
          case PlanSchritt():
            setState(() => _schritt = event.describe());
          case PlanDone(:final bundle, :final kennzahlen):
            setState(() {
              _draft = bundle;
              _uebernommen = kennzahlen?.reuse ?? 0;
              _schritt = null;
            });
          case PlanRevised(:final patch):
            _applyRevision(patch);
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

  /// Schritt [1]: erst die Diagnose, dann entweder Rückfragen oder der Plan.
  ///
  /// Der Halt bei den Rückfragen ist kein Umweg: die Antworten können kippen,
  /// ob die Rückkopplung vorhanden ist oder fehlt — und davon hängt der ganze
  /// Aufbau von Phase 1 ab.
  Future<void> _start() async {
    final token = AppScope.of(context).deviceToken;
    if (token == null) {
      unawaited(_connect());
      return;
    }

    setState(() {
      _diagnosing = true;
      _error = null;
      _schritt = 'Verstehen, worum es geht';
    });

    try {
      final diagnose = await _service(token).starteLauf(
        Eingabe(
          vorhaben: _vorhaben.text,
          stand: _stand.text,
          minutenProTag: _minutenProTag,
          tageProWoche: _tageProWoche,
          equipment: _equipment.text,
        ),
      );
      if (!mounted) return;
      _weiterMitDiagnose(token, diagnose);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _diagnosing = false;
        _schritt = null;
      });
    }
  }

  void _weiterMitDiagnose(String token, Diagnose diagnose) {
    for (final c in _antworten) {
      c.dispose();
    }
    _antworten
      ..clear()
      ..addAll(diagnose.rueckfragen.map((_) => TextEditingController()));

    setState(() {
      _diagnose = diagnose;
      _diagnosing = false;
      _schritt = null;
    });

    if (!diagnose.hatFragen) _listen(_service(token).erzeugePlan(diagnose.laufId));
  }

  /// Schritt [1b]. Leere Felder gelten als übersprungen — jede Frage einzeln.
  Future<void> _antwortenAbsenden() async {
    final token = AppScope.of(context).deviceToken;
    final diagnose = _diagnose;
    if (token == null || diagnose == null) return;

    setState(() {
      _diagnosing = true;
      _error = null;
      _schritt = 'Antworten einarbeiten';
    });

    try {
      final zweite = await _service(token).beantworteRueckfragen(
        diagnose.laufId,
        [
          for (final c in _antworten)
            c.text.trim().isEmpty ? null : c.text.trim(),
        ],
      );
      if (!mounted) return;
      _weiterMitDiagnose(token, zweite);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _diagnosing = false;
        _schritt = null;
      });
    }
  }

  /// Alle Fragen überspringen — der Plan entsteht mit dem, was schon dasteht.
  void _fragenUeberspringen() {
    for (final c in _antworten) {
      c.clear();
    }
    unawaited(_antwortenAbsenden());
  }

  void _revise() {
    final token = AppScope.of(context).deviceToken;
    final draft = _draft;
    if (token == null || draft == null) return;
    _listen(_service(token).revisePlan(draft, _feedback.text));
  }

  void _applyRevision(PlanPatch patch) {
    final draft = _draft;
    if (draft == null) return;
    final result = applyPatch(draft, patch);
    setState(() {
      _draft = result.bundle;
      _skipped = result.skipped;
      _feedback.clear();
    });
    // Eine Überarbeitung verbraucht einen Lauf.
    unawaited(_refreshQuota());
  }

  Future<void> _accept() async {
    final draft = _draft;
    final state = AppScope.of(context);
    final token = state.deviceToken;
    if (draft == null || token == null) return;

    setState(() => _accepting = true);
    final messenger = ScaffoldMessenger.of(context);

    await state.installBundle(draft);

    // Das Teilen darf nicht darüber entscheiden, ob der Nutzer seinen Plan
    // bekommt — er liegt schon in seiner Bibliothek. Geht es schief, ist das
    // eine Randnotiz, kein Fehler.
    var shared = true;
    try {
      await _service(token).acceptPlan(draft);
    } on Exception {
      shared = false;
    }

    if (!mounted) return;
    setState(() => _accepting = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? '// ANGENOMMEN · ÜBUNGEN IN DIE OFFENE BIBLIOTHEK'
              : '// ANGENOMMEN · TEILEN HAT NICHT GEKLAPPT',
        ),
      ),
    );

    final program = draft.programs.isEmpty ? null : draft.programs.first;
    if (program == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramScreen(programId: program.id),
      ),
    );
    if (mounted) setState(() => _draft = null);
  }

  void _discard() {
    setState(() {
      _editing = false;
      _draft = null;
      _diagnose = null;
      _uebernommen = 0;
      _skipped = const [];
      _schritt = null;
      _feedback.clear();
    });
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_draft == null ? 'PLAN ERZEUGEN' : 'PLAN PRÜFEN'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 40),
        children: switch ((_draft, _diagnose)) {
          (final Bundle draft, _) => _reviewView(p, draft),
          (_, final Diagnose d) when d.hatFragen => _questionsView(p, d),
          _ => _askView(p),
        },
      ),
    );
  }

  // -- Anliegen beschreiben --------------------------------------------------

  List<Widget> _askView(Palette p) {
    final quota = _quota;
    final exhausted = quota != null && quota.exhausted;

    final gesperrt = _running || _diagnosing || exhausted;

    return [
      Text(
        'Vier Angaben. Je genauer das Problem, desto besser die Diagnose — der '
        'Plan stellt auf die Ursache ab, nicht auf das Symptom.',
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 11,
          height: 1.65,
          color: p.fgDim,
        ),
      ),

      const SectionLabel('was möchtest du können'),
      _Feld(
        controller: _vorhaben,
        enabled: !gesperrt,
        minLines: 2,
        maxLines: 5,
        hint: 'Ich will Bach vom Blatt spielen können.',
      ),

      const SectionLabel('was kannst du schon'),
      _Feld(
        controller: _stand,
        enabled: !gesperrt,
        minLines: 3,
        maxLines: 8,
        hint:
            'Sechs Jahre Unterricht, spiele nach Gehör gut. Blattspiel habe '
            'ich zweimal angefangen und wieder gelassen.',
      ),

      const SectionLabel('wie viel zeit'),
      _Zeit(
        minutenProTag: _minutenProTag,
        tageProWoche: _tageProWoche,
        enabled: !gesperrt,
        onMinuten: (v) => setState(() => _minutenProTag = v),
        onTage: (v) => setState(() => _tageProWoche = v),
      ),

      const SectionLabel('was steht dir zur verfügung'),
      _Feld(
        controller: _equipment,
        enabled: !gesperrt,
        minLines: 2,
        maxLines: 6,
        hint: 'Geige, Stimmgerät, Handy zum Aufnehmen, Notenständer',
      ),
      const SizedBox(height: 8),
      // Wortgleich aus der Spec (§3): das Feld verhindert, dass die KI im
      // Zweifel den kleinsten gemeinsamen Nenner plant.
      Text(
        'Was steht dir zur Verfügung? Zähl ruhig alles auf, was nützlich sein '
        'könnte — Geräte, Werkzeuge, Räume, Apps, auch Menschen, die dir '
        'helfen könnten. Nicht alles davon wird gebraucht, aber was du nicht '
        'nennst, kann auch nicht eingeplant werden.',
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 10.5,
          height: 1.65,
          color: p.fgDim,
        ),
      ),

      const SizedBox(height: 16),
      if (_running)
        OutlinedButton(onPressed: _cancel, child: const Text('ABBRECHEN'))
      else
        FilledButton(
          onPressed: gesperrt ? null : () => unawaited(_start()),
          child: Text(_diagnosing ? 'WIRD GELESEN…' : 'LOSLEGEN'),
        ),
      ..._progressSection(p),
      const SectionLabel('kontingent'),
      _QuotaBox(quota: quota),
    ];
  }

  // -- Rückfragen ------------------------------------------------------------

  /// Bis zu drei Fragen, jede einzeln überspringbar.
  ///
  /// Sie stehen hier und nicht im ersten Formular, weil erst die Diagnose
  /// weiß, was sie noch braucht. Wer nichts sagen will, kommt trotzdem weiter.
  List<Widget> _questionsView(Palette p, Diagnose diagnose) {
    return [
      if (diagnose.kernproblem.isNotEmpty) ...[
        ZBox(
          title: 'so verstanden',
          filled: true,
          child: Text(
            diagnose.kernproblem,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 11.5,
              height: 1.7,
              color: p.fg,
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
      Text(
        'Diese Antworten würden den Plan verändern. Was du nicht beantwortest, '
        'bleibt offen — der Plan entsteht trotzdem.',
        style: TextStyle(
          fontFamily: Metrics.mono,
          fontSize: 11,
          height: 1.65,
          color: p.fgDim,
        ),
      ),
      for (var i = 0; i < diagnose.rueckfragen.length; i++) ...[
        const SizedBox(height: 16),
        Text(
          diagnose.rueckfragen[i],
          style: TextStyle(
            fontFamily: Metrics.mono,
            fontSize: 11.5,
            height: 1.6,
            color: p.fg,
          ),
        ),
        const SizedBox(height: 8),
        _Feld(
          controller: _antworten[i],
          enabled: !_diagnosing,
          minLines: 2,
          maxLines: 6,
          hint: 'Antwort — oder leer lassen',
        ),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _diagnosing ? null : () => unawaited(_antwortenAbsenden()),
        child: Text(_diagnosing ? 'WIRD GELESEN…' : 'WEITER'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _diagnosing ? null : _fragenUeberspringen,
        child: const Text('ALLE ÜBERSPRINGEN'),
      ),
      ..._progressSection(p),
    ];
  }

  // -- Plan prüfen -----------------------------------------------------------

  List<Widget> _reviewView(Palette p, Bundle draft) {
    final program = draft.programs.isEmpty ? null : draft.programs.first;
    final note = draft.personalNote;
    final wochen = program == null
        ? 0
        : program.phases.fold<int>(0, (s, ph) => s + ph.weeks);

    return [
      if (note != null) ...[
        ZBox(
          title: 'für dich',
          filled: true,
          child: Text(
            note,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 11.5,
              height: 1.7,
              color: p.fg,
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],

      // Die schmale Spalte zwischen persönlicher Nachricht und Plan.
      if (_thoughts.isNotEmpty || _searches.isNotEmpty) ...[
        _ThoughtStrip(
          count: _thoughts.length + _searches.length,
          onTap: () => _showThoughts(context),
        ),
        const SizedBox(height: 14),
      ],

      const SectionLabel('vorschlag'),
      if (program != null)
        ZBox(
          title: 'plan',
          trailing: '${wochen}W',
          // Antippen führt in den Plan selbst — Phasen, Wochen, Tage. Eine
          // Zusammenfassung reicht nicht, um zu entscheiden, ob man ihn will.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProgramScreen(
                programId: program.id,
                preview: draft,
                allowAdopt: false,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                program.name,
                style: TextStyle(
                  fontFamily: Metrics.display,
                  fontSize: 23,
                  height: 1.15,
                  color: p.fg,
                ),
              ),
              if (program.description != null) ...[
                const SizedBox(height: 9),
                Text(
                  program.description!,
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 11,
                    height: 1.65,
                    color: p.fgDim,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final phase in program.phases)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '· ${phase.name} — ${phase.weeks}W',
                    style: TextStyle(
                      fontFamily: Metrics.mono,
                      fontSize: 11,
                      height: 1.5,
                      color: p.fgDim,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                '${draft.exercises.length} ÜBUNGEN · '
                '${draft.routines.length} LISTEN'
                '${_uebernommen == 0 ? "" : " · $_uebernommen ÜBERNOMMEN"}'
                '  ›  ANTIPPEN ZUM ANSEHEN',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: p.fgDim,
                ),
              ),
            ],
          ),
        ),

      if (_skipped.isNotEmpty) ...[
        const SectionLabel('nicht umgesetzt'),
        ZBox(
          title: 'übersprungen',
          accent: p.error,
          filled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in _skipped)
                Text(
                  '· $line',
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 10.5,
                    height: 1.6,
                    color: p.error,
                  ),
                ),
            ],
          ),
        ),
      ],

      const SizedBox(height: 22),
      FilledButton(
        onPressed: _running || _accepting ? null : _accept,
        child: Text(_accepting ? 'WIRD ÜBERNOMMEN…' : 'ANNEHMEN'),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _running || _accepting
                  ? null
                  : () => setState(() => _editing = !_editing),
              child: Text(_editing ? 'ABBRECHEN' : 'BEARBEITEN'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextButton(
              onPressed: _running || _accepting ? null : _discard,
              child: const Text('VERWERFEN'),
            ),
          ),
        ],
      ),

      if (_editing) ...[
        const SectionLabel('was passt nicht'),
        TextField(
          controller: _feedback,
          minLines: 3,
          maxLines: 8,
          autofocus: true,
          enabled: !_running,
          style: TextStyle(
            fontFamily: Metrics.mono,
            fontSize: 11.5,
            height: 1.6,
            color: p.fg,
          ),
          // Bewusst ohne Beispieltext: ein Vorschlag legt nahe, was einem
          // missfallen könnte, und färbt damit die Antwort.
          decoration: const InputDecoration(),
        ),
        const SizedBox(height: 10),
        Text(
          'Geändert wird nur, wovon die Rede ist. Alles andere bleibt so, wie '
          'es hier steht.',
          style: TextStyle(
            fontFamily: Metrics.mono,
            fontSize: 10.5,
            height: 1.65,
            color: p.fgDim,
          ),
        ),
        const SizedBox(height: 12),
        if (_running)
          OutlinedButton(onPressed: _cancel, child: const Text('ABBRECHEN'))
        else
          FilledButton(onPressed: _revise, child: const Text('ÜBERARBEITEN')),
      ],

      ..._progressSection(p),
      const SectionLabel('kontingent'),
      _QuotaBox(quota: _quota),
    ];
  }

  /// Die Gedanken in einem eigenen Fenster: scrollbar, jederzeit wegklickbar.
  Future<void> _showThoughts(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 0),
              child: Text(
                'GEDANKEN',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: Metrics.trackWider,
                  color: p.fg,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
                children: [
                  for (final line in _searches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '→ $line',
                        style: TextStyle(
                          fontFamily: Metrics.mono,
                          fontSize: 10.5,
                          height: 1.55,
                          color: p.accent,
                        ),
                      ),
                    ),
                  for (final line in _thoughts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        line,
                        style: TextStyle(
                          fontFamily: Metrics.mono,
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          height: 1.65,
                          color: p.fgDim,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('SCHLIESSEN'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _progressSection(Palette p) {
    if (!_running && !_diagnosing && _thinking == null && _error == null) {
      return const [];
    }
    return [
      const SectionLabel('verlauf'),
      _Progress(
        running: _running || _diagnosing,
        schritt: _schritt,
        thinking: _thinking,
        searches: _searches,
        chars: _chars,
        error: _error,
      ),
    ];
  }
}

/// Die schmale Spalte zwischen persönlicher Nachricht und Plan.
///
/// Bewusst eine Zeile und kein Kasten: der Gedankengang ist Beiwerk, und wer
/// ihn nicht lesen will, soll nicht daran vorbeiscrollen müssen.
class _ThoughtStrip extends StatelessWidget {
  const _ThoughtStrip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(border: Border.all(color: p.border, width: Metrics.line)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'GEDANKEN NACHLESEN · $count SCHRITTE',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  letterSpacing: 1.3,
                  color: p.fgDim,
                ),
              ),
            ),
            Text(
              '›',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 13,
                color: p.fgDim,
              ),
            ),
          ],
        ),
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
        : 'Noch ${q.remaining} ${q.remaining == 1 ? "Lauf" : "Läufe"} frei, '
              'davon heute ${q.dailyRemaining}. Eine Überarbeitung zählt '
              'genauso wie eine Erzeugung. Abgerechnet wird nur, was auch '
              'ankommt — ein abgebrochener Lauf zählt nicht.';

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
    required this.schritt,
    required this.thinking,
    required this.searches,
    required this.chars,
    required this.error,
  });

  final bool running;
  final String? schritt;
  final String? thinking;
  final List<String> searches;
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
            if (schritt != null)
              Text(
                schritt!.toUpperCase(),
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  height: 1.6,
                  color: p.accent,
                ),
              ),
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
            // Die Suchen sind das Sichtbarste am Wiederverwenden — sie zeigen,
            // dass nicht bei null angefangen wird.
            for (final line in searches) ...[
              const SizedBox(height: 8),
              Text(
                '→ $line',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10,
                  height: 1.5,
                  color: p.accent,
                ),
              ),
            ],
            if (chars > 0) ...[
              const SizedBox(height: 10),
              Text(
                '$chars ZEICHEN',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
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

/// Ein Textfeld im Stil der Eingabemaske. Vier davon statt eines großen
/// Kastens — die Trennung ist Teil der Frage, nicht Zierde.
class _Feld extends StatelessWidget {
  const _Feld({
    required this.controller,
    required this.enabled,
    required this.minLines,
    required this.maxLines,
    required this.hint,
  });

  final TextEditingController controller;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      enabled: enabled,
      style: TextStyle(
        fontFamily: Metrics.mono,
        fontSize: 11.5,
        height: 1.6,
        color: p.fg,
      ),
      decoration: InputDecoration(hintText: hint),
    );
  }
}

/// Minuten pro Tag und Tage pro Woche.
///
/// Als Auswahl und nicht als Freitext: aus „ungefähr eine halbe Stunde" muss
/// der Server sonst eine Zahl raten, und an dieser Zahl hängt, wie viele
/// Übungen in eine Einheit passen.
class _Zeit extends StatelessWidget {
  const _Zeit({
    required this.minutenProTag,
    required this.tageProWoche,
    required this.enabled,
    required this.onMinuten,
    required this.onTage,
  });

  static const minuten = [10, 15, 20, 30, 45, 60, 90, 120];
  static const tage = [1, 2, 3, 4, 5, 6, 7];

  final int minutenProTag;
  final int tageProWoche;
  final bool enabled;
  final ValueChanged<int> onMinuten;
  final ValueChanged<int> onTage;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    Widget zeile(String titel, List<int> werte, int gewaehlt,
        String Function(int) beschriften, ValueChanged<int> onTap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titel,
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10,
              letterSpacing: 1.2,
              color: p.fgDim,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final wert in werte)
                InkWell(
                  onTap: enabled ? () => onTap(wert) : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: wert == gewaehlt ? p.accent : p.border,
                        width: Metrics.line,
                      ),
                    ),
                    child: Text(
                      beschriften(wert),
                      style: TextStyle(
                        fontFamily: Metrics.mono,
                        fontSize: 11,
                        color: wert == gewaehlt ? p.accent : p.fgDim,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        zeile('MINUTEN AM TAG', minuten, minutenProTag, (v) => '$v', onMinuten),
        const SizedBox(height: 12),
        zeile('TAGE DIE WOCHE', tage, tageProWoche, (v) => '$v', onTage),
      ],
    );
  }
}
