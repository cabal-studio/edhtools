import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/auth.dart';
import 'firebase_options.dart'; // generado por `flutterfire configure`
import 'screens/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CommanderSwissApp());
}

class CommanderSwissApp extends StatelessWidget {
  const CommanderSwissApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Edhtools',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Boot(),
    );
  }
}

/// Inicia sesión en silencio (Google o anónimo) antes de mostrar la app.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late Future<void> _f = Auth.ensureSignedIn();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('No se pudo conectar. Revisa tu internet.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: () =>
                          setState(() => _f = Auth.ensureSignedIn()),
                      child: const Text('Reintentar')),
                ]),
              ),
            ),
          );
        }
        return const HomeScreen();
      },
    );
  }
}
