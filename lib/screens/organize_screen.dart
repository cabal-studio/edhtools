import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../logic/league.dart';
import '../logic/swiss.dart';
import '../widgets/league_widgets.dart';
import '../widgets/tournament_tile.dart';
import 'achievements_screen.dart';
import 'groups_screen.dart';
import '../ui/theme.dart';
import 'roster_screen.dart';
import 'tournament_screen.dart';
import 'vote_questions_screen.dart';

class OrganizeScreen extends StatefulWidget {
  /// null = organizar de forma individual; si no, como parte del grupo.
  final Group? group;
  const OrganizeScreen({super.key, this.group});
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

  // Liga
  bool _league = false;
  bool _achOn = false;
  List<Achievement> _achs = [];
  List<String> _tbs = List.of(kDefaultTiebreakers);
  final _max = TextEditingController(text: '0');
  ShareMode _shareAch = ShareMode.end;
  DateTime _date = DateTime.now();
  late final Stream<Group?>? _groupStream =
      widget.group == null ? null : Repo.i.group(widget.group!.id);

  num _n(TextEditingController c, num d) => num.tryParse(c.text.trim()) ?? d;

  Future<void> _create() async {
    setState(() => _busy = true);
    await guard(context, () async {
      final pts = Points(
        win: _n(_win, _league ? 0 : 5),
        draw: _n(_draw, _league ? 0 : 1),
        loss: _n(_loss, 0),
        p2: _n(_p2, 0),
        p3: _n(_p3, 0),
        bye: _n(_bye, 5),
      );
      final name = _name.text.trim();
      final code = _league
          ? await Repo.i.createLeague(
              name: name.isEmpty ? 'Liga Commander' : name,
              roundMinutes: _n(_min, 75).clamp(1, 240).toInt(),
              pts: pts,
              commanderField: _cmd,
              deckListField: _list,
              shareDecks: _shareDecks,
              shareVotes: _shareVotes,
              achievementsOn: _achOn && _achs.isNotEmpty,
              achievements: _achOn ? _achs : const [],
              tiebreakers: _achOn
                  ? _tbs
                  : _tbs.where((k) => !k.startsWith('ach:')).toList(),
              maxScores: _n(_max, 0).toInt().abs(),
              shareAchievements: _shareAch,
              date: _date.millisecondsSinceEpoch,
              group: widget.group,
            )
          : await Repo.i.createTournament(
        group: widget.group,
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
        date: _date.millisecondsSinceEpoch,
      );
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => TournamentScreen(code: code)));
      return;
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
    final g = widget.group;
    final owner = g?.owner;
    return Scaffold(
      appBar: AppBar(
          title: Text(g == null ? 'Organizar torneo' : 'Organizar · ${g.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (g != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.diversity_3, color: kGold),
                title: Text('Organizando como grupo "${g.name}"'),
                subtitle: const Text(
                    'Se usan los mantenedores del grupo y el torneo queda en su historial.'),
              ),
            ),
          if (g == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GroupsScreen())),
                icon: const Icon(Icons.diversity_3),
                label: const Text('Mis grupos de organizadores'),
              ),
            ),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => RosterScreen(
                            owner: owner,
                            title: g == null
                                ? 'Mis jugadores'
                                : 'Jugadores · ${g.name}'))),
                icon: const Icon(Icons.groups),
                label: Text(g == null ? 'Mis jugadores' : 'Jugadores'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => VoteQuestionsScreen(
                            owner: owner,
                            title: g == null
                                ? 'Preguntas de votación'
                                : 'Preguntas · ${g.name}'))),
                icon: const Icon(Icons.how_to_vote),
                label: const Text('Preguntas'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => AchievementsScreen(
                        owner: owner,
                        title: g == null ? 'Logros' : 'Logros · ${g.name}'))),
            icon: const Icon(Icons.military_tech),
            label: const Text('Logros (para ligas)'),
          ),
          const SizedBox(height: 8),
          if (g == null)
            StreamBuilder<Map<String, dynamic>>(
              stream: Repo.i.me(),
              builder: (context, snap) {
                final list = Repo.refs(snap.data ?? const {}, 'organized');
                if (list.isEmpty) return const SizedBox.shrink();
                return _MyList(title: 'Mis torneos', items: list);
              },
            )
          else
            StreamBuilder<Group?>(
              stream: _groupStream,
              builder: (context, snap) {
                final list = snap.data?.tournaments ?? g.tournaments;
                if (list.isEmpty) return const SizedBox.shrink();
                return _MyList(title: 'Torneos del grupo', items: list);
              },
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_league ? 'Nueva liga' : 'Nuevo torneo',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: kGoldLight)),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: false,
                          icon: Icon(Icons.emoji_events_outlined),
                          label: Text('Torneo suizo')),
                      ButtonSegment(
                          value: true,
                          icon: Icon(Icons.calendar_month),
                          label: Text('Liga')),
                    ],
                    selected: {_league},
                    onSelectionChanged: (v) => setState(() {
                      _league = v.first;
                      // Liga: victoria/empate/derrota parten en 0.
                      _win.text = _league ? '0' : '5';
                      _draw.text = _league ? '0' : '1';
                      _loss.text = '0';
                    }),
                  ),
                  if (_league)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                          'Cada ronda se juega cuando quieras (otro día), con su propia clave y los jugadores que se inscriban.',
                          style: TextStyle(color: kMuted, fontSize: 12.5)),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: 'Nombre', hintText: 'Commander Night #12')),
                  const SizedBox(height: 6),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event, color: kGold),
                    title: Text('${_league ? 'Inicio' : 'Fecha'}: ${fmtDate(_date.millisecondsSinceEpoch)}'),
                    subtitle: const Text('Toca para cambiarla'),
                    onTap: () async {
                      final d = await pickDate(context, _date);
                      if (d != null) setState(() => _date = d);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    if (!_league) ...[
                      Expanded(child: _numField('Rondas suizas', _rounds)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: _numField('Minutos por ronda', _min)),
                    if (_league) ...[
                      const SizedBox(width: 10),
                      Expanded(
                          child: _numField('Puntajes máximos (0 = todos)', _max)),
                    ],
                  ]),
                  if (_league)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                          'Puntajes máximos: si eliges 3, el standing suma solo los 3 mejores puntajes de ronda de cada jugador.',
                          style: TextStyle(color: kMuted, fontSize: 12)),
                    ),
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
                  if (_league) ...[
                    const Text('LOGROS Y DESEMPATES',
                        style: TextStyle(color: kGold, fontSize: 12)),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Usar logros'),
                      value: _achOn,
                      onChanged: (v) => setState(() => _achOn = v),
                    ),
                    if (_achOn) ...[
                      AchievementSelector(
                        owner: widget.group?.owner,
                          selected: _achs,
                          onChanged: (v) => setState(() {
                                _achs = v;
                                final ids = v.map((a) => a.id).toSet();
                                _tbs = _tbs
                                    .where((k) =>
                                        !k.startsWith('ach:') ||
                                        ids.contains(k.substring(4)))
                                    .toList();
                              })),
                      ShareModePicker(
                          label: 'Quién ve el detalle de logros',
                          value: _shareAch,
                          onChanged: (v) => setState(() => _shareAch = v)),
                    ],
                    TiebreakEditor(
                        value: _tbs,
                        achievements:
                            _achOn ? {for (final a in _achs) a.id: a} : const {},
                        onChanged: (v) => setState(() => _tbs = v)),
                    const SizedBox(height: 16),
                  ],
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
                        : _league
                            ? 'Crear liga y obtener clave'
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
      for (final t in items) TournamentTile(key: ValueKey(t.code), ref: t),
      const SizedBox(height: 8),
    ]);
  }
}

/// Reutilizado por PlayScreen.
Widget myTournamentList(String title, List<MyTournamentRef> items) =>
    _MyList(title: title, items: items);
