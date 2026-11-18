import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../ui/theme.dart';
import 'organize_screen.dart' show myTournamentList;
import 'tournament_screen.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});
  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  final _code = TextEditingController();
  final _nick = TextEditingController();
  bool _busy = false, _nickLoaded = false;

  Future<void> _go({required bool join}) async {
    final code = _code.text.trim().toUpperCase();
    final nick = _nick.text.trim();
    if (code.length != 6) {
      toast(context, 'La clave tiene 6 caracteres');
      return;
    }
    if (join && nick.isEmpty) {
      toast(context, 'Ingresa tu nombre');
      return;
    }
    setState(() => _busy = true);
    await guard(context, () async {
      final msg = join ? await Repo.i.join(code, nick) : await Repo.i.watch(code);
      if (!mounted) return;
      if (msg != null) toast(context, msg);
      if (msg == 'No existe un torneo con esa clave') return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  TournamentScreen(code: code, startOnMyTable: join)));
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jugar torneo')),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: Repo.i.me(),
        builder: (context, snap) {
          final me = snap.data ?? const {};
          if (!_nickLoaded && snap.hasData) {
            _nickLoaded = true;
            if (_nick.text.isEmpty) _nick.text = '${me['nick'] ?? ''}';
          }
          final list = Repo.refs(me, 'joined');
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Unirme a un torneo',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: kGoldLight)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _code,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp('[A-Za-z0-9]')),
                          TextInputFormatter.withFunction((o, n) =>
                              n.copyWith(text: n.text.toUpperCase())),
                        ],
                        style: const TextStyle(
                            fontSize: 22,
                            letterSpacing: 6,
                            fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                            labelText: 'Clave del torneo', counterText: ''),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nick,
                        maxLength: 24,
                        decoration: const InputDecoration(
                            labelText: 'Tu nombre / nick', counterText: ''),
                        onSubmitted: (_) => _go(join: true),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: FilledButton(
                              onPressed:
                                  _busy ? null : () => _go(join: true),
                              child: const Text('Unirme')),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                            onPressed: _busy ? null : () => _go(join: false),
                            child: const Text('Solo ver')),
                      ]),
                    ]),
              ),
            ),
            if (list.isNotEmpty) myTournamentList('Mis torneos', list),
          ]);
        },
      ),
    );
  }
}
