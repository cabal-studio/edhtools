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

/// Elige qué logros del catálogo usa la liga.
class AchievementSelector extends StatefulWidget {
  final List<Achievement> selected;
  final ValueChanged<List<Achievement>> onChanged;
  const AchievementSelector(
      {super.key, required this.selected, required this.onChanged});
  @override
  State<AchievementSelector> createState() => _AchievementSelectorState();
}

class _AchievementSelectorState extends State<AchievementSelector> {
  late final Stream<List<Achievement>> _stream = Repo.i.achievementCatalog();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Achievement>>(
      stream: _stream,
      builder: (context, snap) {
        final catalog = snap.data ?? const <Achievement>[];
        final selIds = widget.selected.map((a) => a.id).toSet();
        // Logros de la liga que ya no están en el catálogo se conservan.
        final extra = widget.selected.where((a) => !catalog.any((c) => c.id == a.id));
        final all = [...catalog, ...extra];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Logros de la liga (${widget.selected.length})',
              style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 4),
          if (all.isEmpty)
            const Text(
                'Tu catálogo de logros está vacío. Créalos en Organizar → Logros.',
                style: TextStyle(color: kBad, fontSize: 12.5)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final a in all)
              FilterChip(
                label: Text('${a.name} (${a.points})'),
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
      },
    );
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
                  '${a.points} pts${a.bonus != 0 ? ' (+${a.bonus} si ganas)' : ''}',
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

/// Resumen de logros de la liga por jugador (organizador o si se comparten).
class AchievementsSummary extends StatelessWidget {
  final Tournament t;
  final List<LeagueStanding> standings;
  const AchievementsSummary(
      {super.key, required this.t, required this.standings});

  @override
  Widget build(BuildContext context) {
    final achs = t.achievementList;
    if (achs.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Logros obtenidos'),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 12,
            horizontalMargin: 12,
            headingRowHeight: 36,
            columns: [
              const DataColumn(label: Text('JUGADOR', style: TextStyle(color: kMuted, fontSize: 11))),
              for (final a in achs)
                DataColumn(
                    numeric: true,
                    label: Tooltip(
                      message: a.description,
                      child: Text(a.name,
                          style: const TextStyle(color: kMuted, fontSize: 11)),
                    )),
            ],
            rows: [
              for (final s in standings)
                if (s.achCounts.isNotEmpty)
                  DataRow(cells: [
                    DataCell(Text(s.nick)),
                    for (final a in achs)
                      DataCell(Text('${s.achCounts[a.id] ?? ''}')),
                  ]),
            ],
          ),
        ),
      ),
    ]);
  }
}
