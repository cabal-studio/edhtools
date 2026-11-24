import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/league.dart';
import '../logic/swiss.dart';
import '../ui/theme.dart';
import 'common.dart';

/// Ordena los desempates de la liga: los clásicos y logros.
class TiebreakEditor extends StatelessWidget {
  final List<String> value;
  final Map<String, Achievement> achievements;
  final ValueChanged<List<String>> onChanged;
  const TiebreakEditor(
      {super.key,
      required this.value,
      required this.achievements,
      required this.onChanged});

  List<String> get _available => [
        'omw',
        'mw',
        'oomw',
        'wins',
        if (achievements.isNotEmpty) ...['achPos', 'achNeg'],
        for (final a in achievements.values) 'ach:${a.id}',
      ].where((k) => !value.contains(k)).toList();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Desempates (en orden de prioridad)',
          style: TextStyle(color: kMuted, fontSize: 12.5)),
      const SizedBox(height: 4),
      for (var i = 0; i < value.length; i++)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
            title: Text(tiebreakLabel(value[i], achievements)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  tooltip: 'Subir',
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: i == 0
                      ? null
                      : () => onChanged(List.of(value)
                        ..removeAt(i)
                        ..insert(i - 1, value[i]))),
              IconButton(
                  tooltip: 'Bajar',
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: i == value.length - 1
                      ? null
                      : () => onChanged(List.of(value)
                        ..removeAt(i)
                        ..insert(i + 1, value[i]))),
              IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onChanged(List.of(value)..removeAt(i))),
            ]),
          ),
        ),
      if (_available.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<String>(
            onSelected: (k) => onChanged([...value, k]),
            itemBuilder: (_) => [
              for (final k in _available)
                PopupMenuItem(value: k, child: Text(tiebreakLabel(k, achievements))),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: kGold, size: 18),
                SizedBox(width: 4),
                Text('Agregar desempate', style: TextStyle(color: kGold)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Elige la lista de logros (solo activas) y, dentro de ella, qué logros
/// usa la liga. Al cambiar de lista se marcan todos sus logros.
class AchievementSelector extends StatefulWidget {
  final List<Achievement> selected;
  final ValueChanged<List<Achievement>> onChanged;
  final String? listId;
  final ValueChanged<AchList> onListChanged;
  final String? owner;
  const AchievementSelector(
      {super.key,
      required this.selected,
      required this.onChanged,
      required this.listId,
      required this.onListChanged,
      this.owner});
  @override
  State<AchievementSelector> createState() => _AchievementSelectorState();
}

class _AchievementSelectorState extends State<AchievementSelector> {
  late final Stream<List<AchList>> _lists = Repo.i.achLists(owner: widget.owner);
  Stream<List<Achievement>>? _catalog;
  String? _catalogFor;

  Stream<List<Achievement>> _catalogStream(String id) {
    if (_catalogFor != id || _catalog == null) {
      _catalogFor = id;
      _catalog = Repo.i.achievementCatalog(id, owner: widget.owner);
    }
    return _catalog!;
  }

  Future<void> _pick(AchList l) async {
    widget.onListChanged(l);
    final all = await Repo.i.achievementsOnce(l.id, owner: widget.owner);
    widget.onChanged(all);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AchList>>(
      stream: _lists,
      builder: (context, snap) {
        final lists = snap.data ?? const <AchList>[];
        final options = [
          for (final l in lists)
            if (l.active || l.id == widget.listId) l,
        ];
        final current = widget.listId;
        final valid = options.any((l) => l.id == current);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!snap.hasData)
            const LinearProgressIndicator()
          else if (options.isEmpty)
            const Text(
                'No tienes listas de logros activas. Créalas en Organizar → Logros.',
                style: TextStyle(color: kBad, fontSize: 12.5))
          else
            DropdownButtonFormField<String>(
              key: ValueKey('achlist-${valid ? current : ''}'),
              initialValue: valid ? current : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Lista de logros'),
              items: [
                for (final l in options)
                  DropdownMenuItem(
                    value: l.id,
                    child: Text(
                        '${l.name} (${l.count})${l.active ? '' : ' · inactiva'}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) {
                if (id == null || id == current) return;
                _pick(options.firstWhere((l) => l.id == id));
              },
            ),
          const SizedBox(height: 8),
          if (current != null && valid)
            StreamBuilder<List<Achievement>>(
              stream: _catalogStream(current),
              builder: (context, cs) => _chips(cs.data ?? const []),
            )
          else if (widget.selected.isNotEmpty)
            _chips(const []),
        ]);
      },
    );
  }

  Widget _chips(List<Achievement> catalog) {
    final selIds = widget.selected.map((a) => a.id).toSet();
    // Logros de la liga que ya no están en la lista se conservan.
    final extra = widget.selected.where((a) => !catalog.any((c) => c.id == a.id));
    final all = [...catalog, ...extra];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Logros de la liga (${widget.selected.length})',
          style: const TextStyle(color: kMuted, fontSize: 12.5)),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final a in all)
          FilterChip(
            label: Text('${a.name} (${a.points > 0 ? '+' : ''}${a.points})',
                style: a.points < 0 ? const TextStyle(color: kNeg) : null),
            backgroundColor: a.points < 0 ? kNegCard : null,
            selectedColor: a.points < 0 ? kNeg.withValues(alpha: 0.25) : null,
            side: a.points < 0 ? BorderSide(color: kNeg.withValues(alpha: 0.6)) : null,
            tooltip: '${kAchTypeLabels[a.type]} · ${a.description}',
            selected: selIds.contains(a.id),
            onSelected: (v) {
              final next = v
                  ? [...widget.selected, catalog.firstWhere((c) => c.id == a.id, orElse: () => a)]
                  : widget.selected.where((x) => x.id != a.id).toList();
              widget.onChanged(next);
            },
          ),
      ]),
      if (catalog.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => widget.onChanged(catalog),
            child: const Text('Seleccionar todos'),
          ),
        ),
    ]);
  }
}

/// Tarjeta del jugador para reclamar logros durante la ronda.
class ClaimCard extends StatelessWidget {
  final Tournament t;
  final RoundData round;
  final String pid;
  final List<Claim> myClaims;
  const ClaimCard(
      {super.key,
      required this.t,
      required this.round,
      required this.pid,
      required this.myClaims});

  @override
  Widget build(BuildContext context) {
    final mine = myClaims.where((c) => c.round == round.n).toList();
    final achs = t.achievementList;
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kGold.withValues(alpha: .5))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.military_tech, color: kGold),
            SizedBox(width: 8),
            Text('Logros de la ronda',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          Text(
              t.shareAchievements == ShareMode.always
                  ? 'Todos ven los logros obtenidos.'
                  : 'Solo tú y el organizador ven tus logros.',
              style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 8),
          for (final a in achs) _row(context, a, mine.where((c) => c.ach == a.id).toList()),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, Achievement a, List<Claim> got) {
    final canClaim = switch (a.type) {
      AchType.auto => false,
      AchType.player || AchType.round => got.isEmpty,
      AchType.unlimited => true,
    };
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: got.isNotEmpty ? kOk.withValues(alpha: .1) : const Color(0xFF150F27),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: got.isNotEmpty ? kOk.withValues(alpha: .5) : kLine),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${a.name}${got.length > 1 ? ' ×${got.length}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
                [
                  '${a.points > 0 ? '+' : ''}${a.points} pts',
                  kAchTypeLabels[a.type]!,
                  if (a.description.isNotEmpty) a.description,
                ].join(' · '),
                style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        if (got.isNotEmpty && a.type != AchType.auto)
          IconButton(
            tooltip: 'Deshacer',
            icon: const Icon(Icons.undo, size: 18),
            onPressed: () => guard(context,
                () => Repo.i.removeClaim(t.code, got.last.id)),
          ),
        if (a.type == AchType.auto)
          const Icon(Icons.check_circle, color: kOk)
        else if (canClaim)
          FilledButton.tonal(
            onPressed: () => guard(context, () async {
              try {
                await Repo.i.claimAchievement(t.code, a, round.n, pid);
                if (context.mounted) toast(context, 'Logro reclamado: ${a.name}');
              } catch (e) {
                if (!context.mounted) return;
                toast(
                    context,
                    a.type == AchType.round
                        ? 'Otro jugador ya reclamó "${a.name}" en esta ronda'
                        : 'No se pudo reclamar: $e');
              }
            }),
            child: const Text('Reclamar'),
          )
        else
          const Icon(Icons.check_circle, color: kOk),
      ]),
    );
  }
}

/// Organizador: ver y modificar los logros de cada jugador en la ronda.
class RoundClaimsAdmin extends StatelessWidget {
  final Tournament t;
  final RoundData round;
  final Map<String, PlayerData> players;
  final List<Claim> claims;
  final bool editable;
  const RoundClaimsAdmin(
      {super.key,
      required this.t,
      required this.round,
      required this.players,
      required this.claims,
      required this.editable});

  @override
  Widget build(BuildContext context) {
    final rc = claims.where((c) => c.round == round.n).toList();
    final seated = [
      for (final tb in round.tables) ...tb.seats,
      ...round.byes,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Logros de la ronda ${round.n} (${rc.length})'),
      for (final pid in seated)
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 110,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(players[pid]?.nick ?? '¿?',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              Expanded(
                child: Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final c in rc.where((c) => c.pid == pid))
                    InputChip(
                      label: Text(t.achievements[c.ach]?.name ?? c.ach),
                      visualDensity: VisualDensity.compact,
                      onDeleted: editable
                          ? () => guard(context, () => Repo.i.removeClaim(t.code, c.id))
                          : null,
                    ),
                  if (editable)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('Logro'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _add(context, pid, rc),
                    ),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }

  Future<void> _add(BuildContext context, String pid, List<Claim> rc) async {
    final a = await showDialog<Achievement>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text('Logro para ${players[pid]?.nick ?? ''}'),
        children: [
          for (final a in t.achievementList)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, a),
              child: Text('${a.name} · ${a.points} pts · ${kAchTypeLabels[a.type]}'),
            ),
        ],
      ),
    );
    if (a == null || !context.mounted) return;
    if (a.type == AchType.round) {
      final other = rc.where((c) => c.ach == a.id).toList();
      if (other.isNotEmpty) {
        final ok = await confirmDialog(context,
            '"${a.name}" ya lo tiene ${players[other.first.pid]?.nick}. ¿Asignárselo a ${players[pid]?.nick} en su lugar?',
            ok: 'Reasignar');
        if (!ok || !context.mounted) return;
        await guard(context, () => Repo.i.removeClaim(t.code, other.first.id));
      }
    }
    if (!context.mounted) return;
    await guard(context, () => Repo.i.claimAchievement(t.code, a, round.n, pid));
  }
}

/// Logros obtenidos: una tabla por ronda y una tabla con el total de la
/// liga. Cada tabla muestra cuántas veces obtuvo cada logro el jugador y la
/// suma de puntos de logros (los negativos restan).
class AchievementsSummary extends StatelessWidget {
  final Tournament t;
  final List<LeagueStanding> standings;
  final List<RoundData> rounds;
  final List<Claim> claims;
  const AchievementsSummary(
      {super.key,
      required this.t,
      required this.standings,
      required this.rounds,
      required this.claims});

  static String _sign(num v) => v > 0 ? '+$v' : '$v';

  Widget _table(List<Achievement> achs, Iterable<Claim> cs) {
    const hs = TextStyle(color: kMuted, fontSize: 11);
    final counts = <String, Map<String, int>>{};
    final pts = <String, num>{};
    for (final c in cs) {
      final a = t.achievements[c.ach];
      if (a == null) continue;
      final m = counts.putIfAbsent(c.pid, () => {});
      m[c.ach] = (m[c.ach] ?? 0) + 1;
      pts[c.pid] = (pts[c.pid] ?? 0) + a.points;
    }
    if (counts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Nadie obtuvo logros.', style: TextStyle(color: kMuted)),
      );
    }
    final order = [
      for (final s in standings)
        if (counts.containsKey(s.id)) s,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 12,
        horizontalMargin: 12,
        headingRowHeight: 36,
        columns: [
          const DataColumn(label: Text('JUGADOR', style: hs)),
          for (final a in achs)
            DataColumn(
                numeric: true,
                label: Tooltip(
                  message: '${a.description} (${_sign(a.points)} pts)',
                  child: Text('${a.name} (${_sign(a.points)})', style: hs),
                )),
          const DataColumn(label: Text('PTS LOGROS', style: hs), numeric: true),
        ],
        rows: [
          for (final s in order)
            DataRow(cells: [
              DataCell(Text(s.nick)),
              for (final a in achs)
                DataCell(Text('${counts[s.id]![a.id] ?? ''}')),
              DataCell(Text(_sign(pts[s.id] ?? 0),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: (pts[s.id] ?? 0) < 0 ? Colors.redAccent : kGoldLight))),
            ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final achs = t.achievementList;
    if (achs.isEmpty) return const SizedBox.shrink();
    final ns = rounds.map((r) => r.n).toList()..sort();
    final inScope = claims.where((c) => ns.contains(c.round)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Logros obtenidos'),
      for (final n in ns.reversed)
        Card(
          child: ExpansionTile(
            initiallyExpanded: n == ns.last,
            shape: const Border(),
            title: Text('Ronda $n',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            children: [_table(achs, inScope.where((c) => c.round == n))],
          ),
        ),
      Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Total de la liga',
                style: TextStyle(fontWeight: FontWeight.w700, color: kGold)),
          ),
          _table(achs, inScope),
        ]),
      ),
    ]);
  }
}
