import 'package:flutter/material.dart';

import 'data/storage.dart';
import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(Store(FileStorageBackend()));
  runApp(ProgramsApp(state: state));
}

/// Reicht den [AppState] durch den Baum. Bewusst ohne externe
/// State-Management-Bibliothek — ein Datenstamm, ein Notifier.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope fehlt über diesem Widget');
    return scope!.notifier!;
  }
}

class ProgramsApp extends StatefulWidget {
  const ProgramsApp({super.key, required this.state});

  final AppState state;

  @override
  State<ProgramsApp> createState() => _ProgramsAppState();
}

class _ProgramsAppState extends State<ProgramsApp> {
  late final Future<void> _ready = widget.state.init();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: 'LevelUp',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // Papier als Standard. Die Palette stammt aus ZENTRALE, wo `day` der
        // Normalfall ist und `night` die Ausnahme.
        themeMode: ThemeMode.light,
        home: FutureBuilder<void>(
          future: _ready,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return _StartupError(error: snapshot.error!);
            }
            return const HomeScreen();
          },
        ),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              const Text('Die Bibliothek konnte nicht geladen werden.'),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
