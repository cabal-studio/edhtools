import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/swiss.dart';
import '../ui/theme.dart';
import 'common.dart';

enum TableMode { org, mine, view }

/// Una mesa de la ronda: resultados (organizador), reporte (jugador) o lectura.
class TableCard extends StatelessWidget {
  final Tournament t;
  final RoundData round;
  final TableData table;
  final TableMode mode;
  final Map<String, PlayerData> players;
  final Map<String, num> totals;
  final Map<String, DeckInfo> decks;
  final Report? report;
  final String? myPid;

  // Organizador
  final void Function(String pid, String v)? onResult;
  final VoidCallback? onDrawAll;
  final VoidCallback? onClear;
  final VoidCallback? onApplyReport;

  // Jugador
  final Map<String, String> draft;
  final void Function(String pid, String v)? onDraft;
  final VoidCallback? onSendReport;

  const TableCard({
    super.key,
    required this.t,
    required this.round,
    required this.table,
    required this.mode,
    required this.players,
    required this.totals,
    this.decks = const {},
    this.report,
    this.myPid,
    this.onResult,
    this.onDrawAll,
    this.onClear,
    this.onApplyReport,
    this.draft = const {},
    this.onDraft,
    this.onSendReport,
  });

  String nick(String id) => players[id]?.nick ?? '¿?';

  bool _sameRes(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  Widget build(BuildContext context) {
    final tb = table;
    final rows = <Widget>[];
    for (var i = 0; i < tb.seats.length; i++) {
      final pid = tb.seats[i];
      final dropped = players[pid]?.dropped ?? false;
      final deck = decks[pid];
      final Widget trailing = switch (mode) {
        TableMode.org => ResultChips(
            pts: t.pts, current: tb.res[pid], onPick: (v) => onResult?.call(pid, v)),
        TableMode.mine => ResultChips(
            pts: t.pts, current: draft[pid], onPick: (v) => onDraft?.call(pid, v)),
        TableMode.view => ResultBadge(pts: t.pts, value: tb.res[pid]),
      };
      rows.add(Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: pid == myPid ? const Color(0x268B6CF0) : null,
          borderRadius: BorderRadius.circular(10),
          border: const Border(top: BorderSide(color: Color(0x0DFFFFFF))),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            CircleAvatar(
                radius: 12,
                backgroundColor: const Color(0xFF150F27),
                child: Text('${i + 1}',
                    style: const TextStyle(fontSize: 12, color: kMuted))),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 110, maxWidth: 260),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nick(pid) + (dropped ? ' (drop)' : ''),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '${totals[pid] ?? 0} pts'
                        '${deck != null && deck.commander.isNotEmpty ? ' · ${deck.commander}' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  ]),
            ),
            trailing,
          ],
        ),
      ));
    }

    final footer = <Widget>[];
    if (mode == TableMode.org) {
      footer.add(Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: onDrawAll, child: const Text('Empate en mesa')),
        TextButton(onPressed: onClear, child: const Text('Limpiar')),
      ]));
      final rep = report;
      if (rep != null && !_sameRes(rep.res, tb.res)) {
        footer.add(Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: kBlue.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBlue.withValues(alpha: .4))),
          child: Row(children: [
            Expanded(
              child: Text(
                  '📩 Reporte de ${nick(rep.by)}: ${tb.seats.map((p) => '${nick(p)} ${kResultLabels[rep.res[p]] ?? '—'}').join(' · ')}',
                  style: const TextStyle(fontSize: 13)),
            ),
            FilledButton.tonal(
                onPressed: onApplyReport, child: const Text('Aplicar')),
          ]),
        ));
      }
    }
    if (mode == TableMode.mine) {
      final full = tb.seats.every((p) => draft[p] != null);
      footer.addAll([
        const SizedBox(height: 8),
        const Text(
            'Reporta el resultado de tu mesa. El organizador lo revisa antes de enviar los puntos.',
            style: TextStyle(color: kMuted, fontSize: 12.5)),
        if (report != null)
          Text('Reporte enviado por ${nick(report!.by)} ✓',
              style: const TextStyle(color: kOk, fontSize: 13)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: full ? onSendReport : null,
          child: const Text('Enviar resultado'),
        ),
      ]);
    }

    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: tb.complete ? kOk.withValues(alpha: .4) : kLine)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text('Mesa ${tb.t}',
                  style: const TextStyle(
                      color: kGoldLight,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('${tb.seats.length} jugadores',
                  style: const TextStyle(color: kMuted)),
              if (tb.complete) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check, color: kOk, size: 18)
              ],
            ]),
            ...rows,
            ...footer,
          ],
        ),
      ),
    );
  }
}
