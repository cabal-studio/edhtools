import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../logic/swiss.dart';
import '../ui/theme.dart';
import 'roster_screen.dart';
import 'tournament_screen.dart';
import 'vote_questions_screen.dart';

class OrganizeScreen extends StatefulWidget {
  const OrganizeScreen({super.key});
  @override
  State<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends State<OrganizeScreen> {
  final _name = TextEditingController();
  final _rounds = TextEditingController(text: '4');
  final _min = TextEditingController(text: '75');
  final _win = TextEditingController(text: '5');
  final _draw = TextEditingController(text: '1');
  final _loss = TextEditingController(text: '0');
  final _p2 = TextEditingController(text: '0');
  final _p3 = TextEditingController(text: '0');
  final _bye = TextEditingController(text: '5');
  FieldMode _cmd = FieldMode.optional;
  FieldMode _list = FieldMode.optional;
  ShareMode _shareDecks = ShareMode.end;
  ShareMode _shareVotes = ShareMode.never;
  bool _busy = false;

  num _n(TextEditingController c, num d) => num.tryParse(c.text.trim()) ?? d;

  Future<void> _create() async {
    setState(() => _busy = true);
    await guard(context, () async {
      final code = await Repo.i.createTournament(
        name: _name.text.trim().isEmpty ? 'Torneo Commander' : _name.text.trim(),
        rounds: _n(_rounds, 4).clamp(1, 15).toInt(),
        roundMinutes: _n(_min, 75).clamp(1, 240).toInt(),
        pts: Points(
          win: _n(_win, 5),
          draw: _n(_draw, 1),
          loss: _n(_loss, 0),
          p2: _n(_p2, 0),
          p3: _n(_p3, 0),
          bye: _n(_bye, 5),
        ),
        commanderField: _cmd,
        deckListField: _list,
        shareDecks: _shareDecks,
        shareVotes: _shareVotes,
      );
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => TournamentScreen(code: code)));
    });
    if (mounted) setState(() => _busy = false);
  }

  Widget _numField(String label, TextEditingController c) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(labelText: label),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organizar torneo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RosterScreen())),
                icon: const Icon(Icons.groups),
                label: const Text('Mis jugadores'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const VoteQuestionsScreen())),
                icon: const Icon(Icons.how_to_vote),
                label: const Text('Preguntas'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          StreamBuilder<Map<String, dynamic>>(
            stream: Repo.i.me(),
            builder: (context, snap) {
              final list = Repo.refs(snap.data ?? const {}, 'organized');
              if (list.isEmpty) return const SizedBox.shrink();
              return _MyList(title: 'Mis torneos', items: list);
            },
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Nuevo torneo',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: kGoldLight)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: 'Nombre', hintText: 'Commander Night #12')),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _numField('Rondas suizas', _rounds)),
                    const SizedBox(width: 10),
                    Expanded(child: _numField('Minutos por ronda', _min)),
                  ]),
                  const SizedBox(height: 16),
                  const Text('PUNTOS POR MESA',
                      style: TextStyle(color: kGold, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _numField('Victoria', _win)),
                    const SizedBox(width: 8),
                    Expanded(child: _numField('Empate', _draw)),
                    const SizedBox(width: 8),
                    Expanded(child: _numField('Derrota', _loss)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _numField('2º lugar', _p2)),
                    const SizedBox(width: 8),
                    Expanded(child: _numField('3º lugar', _p3)),
                    const SizedBox(width: 8),
                    Expanded(child: _numField('Bye', _bye)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Si 2º o 3º valen más de 0 podrás registrar posiciones. '
                    'El bye solo ocurre con 5 jugadores (mesa de 4 + 1 libre).',
                    style: TextStyle(color: kMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  const Text('INSCRIPCIÓN Y PRIVACIDAD',
                      style: TextStyle(color: kGold, fontSize: 12)),
                  FieldModePicker(
                      label: 'Baraja / Comandante',
                      value: _cmd,
                      onChanged: (v) => setState(() => _cmd = v)),
                  FieldModePicker(
                      label: 'Lista de la baraja (URL)',
                      value: _list,
                      onChanged: (v) => setState(() => _list = v)),
                  ShareModePicker(
                      label: 'Quién ve las barajas',
                      value: _shareDecks,
                      onChanged: (v) => setState(() => _shareDecks = v)),
                  ShareModePicker(
                      label: 'Quién ve los votos especiales',
                      value: _shareVotes,
                      onChanged: (v) => setState(() => _shareVotes = v)),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _busy ? null : _create,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16)),
                    child: Text(_busy
                        ? 'Creando…'
                        : 'Crear torneo y obtener clave'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MyList extends StatelessWidget {
  final String title;
  final List<MyTournamentRef> items;
  const _MyList({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(title.toUpperCase(),
            style: const TextStyle(color: kMuted, fontSize: 12)),
      ),
      for (final t in items)
        Card(
          child: ListTile(
            title: Text(t.name),
            trailing: Text(t.code,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    color: kGoldLight,
                    letterSpacing: 2)),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TournamentScreen(code: t.code))),
          ),
        ),
      const SizedBox(height: 8),
    ]);
  }
}

/// Reutilizado por PlayScreen.
Widget myTournamentList(String title, List<MyTournamentRef> items) =>
    _MyList(title: title, items: items);
