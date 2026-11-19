import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../screens/roster_screen.dart' show KindBadge;
import '../ui/theme.dart';

class RosterPick {
  /// Persona existente del mantenedor, o null si es un jugador nuevo.
  final RosterPerson? person;
  final String nick;
  const RosterPick(this.person, this.nick);
}

/// Elige un jugador del mantenedor para agregarlo al torneo, o crea uno nuevo.
Future<RosterPick?> pickRosterPlayer(
    BuildContext context, Set<String> alreadyIn, {String? owner}) {
  return showDialog<RosterPick>(
    context: context,
    builder: (c) => _RosterPicker(alreadyIn: alreadyIn, owner: owner),
  );
}

class _RosterPicker extends StatefulWidget {
  final Set<String> alreadyIn;
  final String? owner;
  const _RosterPicker({required this.alreadyIn, this.owner});
  @override
  State<_RosterPicker> createState() => _RosterPickerState();
}

class _RosterPickerState extends State<_RosterPicker> {
  final _q = TextEditingController();
  late final Stream<List<RosterPerson>> _stream =
      Repo.i.rosterPeople(owner: widget.owner);

  void _new() {
    final n = _q.text.trim();
    if (n.isEmpty) return;
    Navigator.pop(context, RosterPick(null, n));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar jugador'),
      content: SizedBox(
        width: 420,
        height: 440,
        child: StreamBuilder<List<RosterPerson>>(
          stream: _stream,
          builder: (context, snap) {
            final q = _q.text.trim().toLowerCase();
            final all = snap.data ?? const <RosterPerson>[];
            final list = all
                .where((p) =>
                    !widget.alreadyIn.contains(p.id) &&
                    (q.isEmpty || p.nick.toLowerCase().contains(q)))
                .toList();
            final exact = all.any((p) => p.nick.toLowerCase() == q);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _q,
                autofocus: true,
                maxLength: 24,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Nombre del jugador',
                    counterText: ''),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => list.length == 1
                    ? Navigator.pop(context, RosterPick(list.first, list.first.nick))
                    : _new(),
              ),
              if (q.isNotEmpty && !exact)
                ListTile(
                  leading: const Icon(Icons.person_add, color: kGold),
                  title: Text('Nuevo jugador: "${_q.text.trim()}"'),
                  subtitle: const Text('Se guardará en Mis jugadores'),
                  onTap: _new,
                ),
              const Divider(),
              Text(
                  list.isEmpty
                      ? (all.isEmpty
                          ? 'Aún no tienes jugadores guardados. Escribe un nombre para crear uno.'
                          : 'Sin coincidencias.')
                      : 'Jugadores guardados',
                  style: const TextStyle(color: kMuted, fontSize: 12)),
              Expanded(
                child: ListView(children: [
                  for (final p in list)
                    ListTile(
                      dense: true,
                      title: Text(p.nick),
                      subtitle: Text('${p.tournamentCount} torneo(s)'),
                      trailing: KindBadge(p),
                      onTap: () => Navigator.pop(context, RosterPick(p, p.nick)),
                    ),
                ]),
              ),
            ]);
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}
