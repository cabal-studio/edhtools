import 'package:flutter/material.dart';

import '../logic/swiss.dart';
import '../ui/theme.dart';

/// Editor de mesas para la preparación de una ronda.
///
/// * Mantener presionado y arrastrar un jugador sobre otro: se intercambian.
/// * Arrastrarlo sobre el título de una mesa, "Bye" o "Nueva mesa": se mueve.
/// * Alternativa táctil: tocar un jugador (queda marcado) y luego tocar otro
///   jugador o el botón "Mover aquí" de una mesa.
class PrepEditor extends StatefulWidget {
  final RoundData round;
  final Map<String, PlayerData> players;

  /// Puntos acumulados antes de esta ronda, para mostrar junto a cada jugador.
  final Map<String, num> points;
  final void Function(List<TableData> tables, List<String> byes) onChanged;

  const PrepEditor({
    super.key,
    required this.round,
    required this.players,
    required this.points,
    required this.onChanged,
  });

  @override
  State<PrepEditor> createState() => _PrepEditorState();
}

class _PrepEditorState extends State<PrepEditor> {
  String? selected;

  RoundData get r => widget.round;
  String nick(String id) => widget.players[id]?.nick ?? '¿?';

  void _apply({required String pid, String? targetPid, int? toTable, bool toBye = false}) {
    final res = movePlayer(r.tables, r.byes,
        pid: pid, targetPid: targetPid, toTable: toTable, toBye: toBye);
    setState(() => selected = null);
    widget.onChanged(res.tables, res.byes);
  }

  void _tap(String pid) {
    if (selected == null) {
      setState(() => selected = pid);
    } else if (selected == pid) {
      setState(() => selected = null);
    } else {
      _apply(pid: selected!, targetPid: pid);
    }
  }

  Widget _chip(String pid, {int? seat, bool highlight = false}) {
    final sel = selected == pid;
    final dropped = widget.players[pid]?.dropped ?? false;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: sel
            ? kGold.withValues(alpha: .25)
            : highlight
                ? kBlue.withValues(alpha: .2)
                : const Color(0xFF150F27),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sel ? kGold : (highlight ? kBlue : kLine)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (seat != null) ...[
          CircleAvatar(
              radius: 11,
              backgroundColor: kCard,
              child: Text('$seat',
                  style: const TextStyle(fontSize: 11, color: kMuted))),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(nick(pid) + (dropped ? ' (drop)' : ''),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: dropped ? kBad : null)),
        ),
        const SizedBox(width: 8),
        Text('${widget.points[pid] ?? 0} pts',
            style: const TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(width: 4),
        const Icon(Icons.drag_indicator, size: 16, color: kMuted),
      ]),
    );
  }

  Widget _player(String pid, {int? seat}) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != pid,
      onAcceptWithDetails: (d) => _apply(pid: d.data, targetPid: pid),
      builder: (context, cand, _) {
        final child = _chip(pid, seat: seat, highlight: cand.isNotEmpty);
        return LongPressDraggable<String>(
          data: pid,
          feedback: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: _chip(pid, seat: seat, highlight: true),
            ),
          ),
          childWhenDragging: Opacity(opacity: .3, child: child),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _tap(pid),
            child: child,
          ),
        );
      },
    );
  }

  Widget _zone({
    required String title,
    required List<String> pids,
    required void Function(String pid) onDrop,
    String? subtitle,
    Color? accent,
    bool numbered = false,
  }) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => !pids.contains(d.data) || !numbered,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, cand, _) => Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: cand.isNotEmpty ? kBlue : (accent ?? kLine),
              width: cand.isNotEmpty ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(title,
                  style: const TextStyle(
                      color: kGoldLight,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              if (subtitle != null)
                Expanded(
                    child: Text(subtitle,
                        style: TextStyle(color: accent ?? kMuted, fontSize: 12.5)))
              else
                const Spacer(),
              if (selected != null && !pids.contains(selected))
                TextButton.icon(
                  onPressed: () => onDrop(selected!),
                  icon: const Icon(Icons.call_received, size: 16),
                  label: const Text('Mover aquí'),
                ),
            ]),
            for (var i = 0; i < pids.length; i++)
              _player(pids[i], seat: numbered ? i + 1 : null),
            if (pids.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Arrastra jugadores aquí',
                    style: TextStyle(color: kMuted, fontSize: 12.5)),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seated = r.seated;
    final unseated = widget.players.values
        .where((p) => !p.dropped && !seated.contains(p.id))
        .map((p) => p.id)
        .toList();
    final nextTable = r.tables.length + 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
        'Mantén presionado y arrastra un jugador sobre otro para '
        'intercambiarlos, o tócalos uno después del otro. El número de '
        'asiento es el orden de turno.',
        style: TextStyle(color: kMuted, fontSize: 12.5),
      ),
      if (r.repeats > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              '${r.repeats} par(es) de jugadores repiten mesa con una ronda anterior.',
              style: const TextStyle(color: kGold, fontSize: 12.5)),
        ),
      if (unseated.isNotEmpty)
        _zone(
          title: 'Sin mesa',
          subtitle: 'Asígnalos antes de empezar la ronda',
          accent: kBad,
          pids: unseated,
          onDrop: (pid) => _apply(pid: pid),
        ),
      for (final tb in r.tables)
        _zone(
          title: 'Mesa ${tb.t}',
          subtitle: tb.seats.length < 3
              ? '${tb.seats.length} jugadores: muy pocos'
              : tb.seats.length > 5
                  ? '${tb.seats.length} jugadores: demasiados'
                  : '${tb.seats.length} jugadores',
          accent: tb.seats.length < 3 || tb.seats.length > 5 ? kBad : null,
          pids: tb.seats,
          numbered: true,
          onDrop: (pid) => _apply(pid: pid, toTable: tb.t),
        ),
      _zone(
        title: 'Bye',
        subtitle: 'Recibe los puntos de bye sin jugar',
        pids: r.byes,
        onDrop: (pid) => _apply(pid: pid, toBye: true),
      ),
      _zone(
        title: 'Nueva mesa',
        subtitle: 'Suelta aquí para abrir la mesa $nextTable',
        pids: const [],
        onDrop: (pid) => _apply(pid: pid, toTable: nextTable),
      ),
    ]);
  }
}

/// Puntos acumulados por jugador en las rondas dadas.
Map<String, num> pointsBy(
        List<RoundData> rounds, Map<String, PlayerData> ps, Points pts) =>
    {for (final s in computeStandings(rounds, ps, pts)) s.id: s.pts};

/// Advertencias que impiden (o recomiendan no) empezar la ronda.
List<String> prepWarnings(RoundData r, Map<String, PlayerData> ps) {
  final out = <String>[];
  final seated = r.seated;
  final unseated =
      ps.values.where((p) => !p.dropped && !seated.contains(p.id)).length;
  if (unseated > 0) out.add('$unseated jugador(es) sin mesa');
  final small = r.tables.where((t) => t.seats.length < 3).length;
  if (small > 0) out.add('$small mesa(s) con menos de 3 jugadores');
  final droppedSeated =
      seated.where((id) => ps[id]?.dropped ?? false).length;
  if (droppedSeated > 0) out.add('$droppedSeated jugador(es) con drop en mesa');
  return out;
}
