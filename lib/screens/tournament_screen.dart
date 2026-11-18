import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../logic/swiss.dart';
import '../ui/theme.dart';

class TournamentScreen extends StatefulWidget {
  final String code;
  final bool startOnMyTable;
  const TournamentScreen(
      {super.key, required this.code, this.startOnMyTable = false});

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

enum _Tab { mine, tables, standing, players, settings }

class _TournamentScreenState extends State<TournamentScreen> {
  final _repo = Repo.i;
  final _subs = <StreamSubscription>[];
  Tournament? t;
  bool loaded = false;
  Map<String, PlayerData> players = {};
  Map<int, RoundData> rounds = {};
  Map<String, Report> reports = {};
  final Map<String, Map<String, String>> drafts = {};
  int? viewRound;
  bool prelim = false;
  _Tab? tab;

  String get code => widget.code;
  String get uid => FirebaseAuth.instance.currentUser!.uid;
  bool get isOrg => t != null && t!.organizerId == uid;
  String? get myPid => players.containsKey(uid) ? uid : null;
  RoundData? get current => t == null ? null : rounds[t!.currentRound];
  List<RoundData> get roundList =>
      rounds.values.toList()..sort((a, b) => a.n.compareTo(b.n));
  List<RoundData> get confirmed =>
      roundList.where((r) => r.confirmed).toList();
  String nick(String id) => players[id]?.nick ?? '¿?';

  @override
  void initState() {
    super.initState();
    if (widget.startOnMyTable) tab = _Tab.mine;
    void onErr(Object e) {
      if (mounted) toast(context, 'Error de conexión: $e');
    }

    _subs.add(_repo.tournament(code).listen((v) {
      setState(() {
        t = v;
        loaded = true;
      });
    }, onError: onErr));
    _subs.add(_repo.players(code).listen((v) => setState(() => players = v),
        onError: onErr));
    _subs.add(_repo.rounds(code).listen((v) => setState(() => rounds = v),
        onError: onErr));
    _subs.add(_repo.reports(code).listen((v) => setState(() => reports = v),
        onError: onErr));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = this.t;
    if (t == null) {
      return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text('No existe un torneo con la clave $code')));
    }
    final tabs = isOrg
        ? [_Tab.tables, _Tab.standing, _Tab.players, _Tab.settings]
        : [_Tab.mine, _Tab.tables, _Tab.standing];
    if (tab == null || !tabs.contains(tab)) {
      tab = isOrg && t.status == 'registration' ? _Tab.players : tabs.first;
    }

    Widget body;
    switch (tab!) {
      case _Tab.mine:
        body = _myTable(t);
      case _Tab.tables:
        body = _tables(t);
      case _Tab.standing:
        body = _standing(t);
      case _Tab.players:
        body = _players(t);
      case _Tab.settings:
        body = _SettingsForm(t: t);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.name, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              label: Text(isOrg
                  ? 'Organizador'
                  : myPid != null
                      ? 'Jugador'
                      : 'Espectador'),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
        children: [
          _header(t),
          if (isOrg) _orgPanel(t),
          const SizedBox(height: 6),
          body,
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabs.indexOf(tab!),
        onDestinationSelected: (i) => setState(() => tab = tabs[i]),
        destinations: [for (final x in tabs) _destination(x)],
      ),
    );
  }

  Widget _header(Tournament t) {
    final active = players.values.where((p) => !p.dropped).length;
    final (label, color) = switch (t.status) {
      'registration' => ('Inscripción', kBlue),
      'round' => ('Ronda ${t.currentRound} en juego', kOk),
      'review' => ('Revisión ronda ${t.currentRound}', kGold),
      _ => ('Finalizado', kMuted),
    };
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (mounted) toast(context, 'Clave copiada: $code');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kGold.withValues(alpha: .5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('CLAVE ',
                    style: TextStyle(color: kMuted, fontSize: 11)),
                Text(code,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 22,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w700,
                        color: kGoldLight)),
                const SizedBox(width: 6),
                const Icon(Icons.copy, size: 16, color: kMuted),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(99)),
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                Text(
                    '$active jugadores · ${t.rounds} rondas · ${t.roundMinutes} min',
                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
              ]),
        ]),
      ),
      if (t.status == 'round' || t.status == 'review') _TimerBox(t: t),
    ]);
  }

  Widget _orgPanel(Tournament t) {
    final children = <Widget>[];
    switch (t.status) {
      case 'registration':
        final n = players.values.where((p) => !p.dropped).length;
        children.addAll([
          Text(
              'Comparte la clave $code para que los jugadores se inscriban. '
              'Sugerido para $n jugadores: ${suggestedRounds(n)} rondas.'),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: n < 3
                ? null
                : () async {
                    if (!await confirmDialog(context,
                        '¿Comenzar con $n jugadores? Se generará la ronda 1.',
                        ok: 'Comenzar')) {
                      return;
                    }
                    if (!mounted) return;
                    await guard(
                        context, () => _repo.startTournament(t, players));
                    setState(() {
                      tab = _Tab.tables;
                      viewRound = null;
                    });
                  },
            child: Text(n < 3
                ? 'Necesitas al menos 3 jugadores'
                : 'Comenzar torneo · Ronda 1'),
          ),
        ]);
      case 'round':
        children.addAll([
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () => guard(context, () => _repo.togglePause(t)),
                icon: Icon(t.timerPaused != null ? Icons.play_arrow : Icons.pause),
                label: Text(t.timerPaused != null ? 'Reanudar' : 'Pausar')),
            OutlinedButton(
                onPressed: () => guard(context, () => _repo.addMinutes(t, -5)),
                child: const Text('−5 min')),
            OutlinedButton(
                onPressed: () => guard(context, () => _repo.addMinutes(t, 5)),
                child: const Text('+5 min')),
            OutlinedButton.icon(
                onPressed: () async {
                  if (await confirmDialog(
                          context, '¿Reiniciar el reloj al tiempo completo?') &&
                      mounted) {
                    await guard(context, () => _repo.resetTimer(t));
                  }
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reiniciar')),
          ]),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () async {
              if (await confirmDialog(context,
                      '¿Terminar la ronda ${t.currentRound}? Pasarás a revisar los puntos.',
                      ok: 'Terminar ronda') &&
                  mounted) {
                await guard(context, () => _repo.setStatus(code, 'review'));
                setState(() => tab = _Tab.tables);
              }
            },
            child: Text('Terminar ronda ${t.currentRound} y revisar puntos'),
          ),
        ]);
      case 'review':
        final r = current;
        final miss = r?.tables.where((x) => !x.complete).length ?? 0;
        final last = t.currentRound >= t.rounds;
        children.addAll([
          Text('Revisión de la ronda ${t.currentRound}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            miss > 0
                ? '$miss mesa(s) sin resultado completo.'
                : 'Todas las mesas tienen resultado ✓',
            style: TextStyle(color: miss > 0 ? kBad : kOk),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: () =>
                    guard(context, () => _repo.setStatus(code, 'round')),
                child: const Text('‹ Volver a la ronda')),
          ),
          FilledButton(
            onPressed: () async {
              final msg = miss > 0
                  ? 'Hay $miss mesa(s) sin resultado completo; esos jugadores suman 0. ¿Confirmar igual?'
                  : last
                      ? '¿Confirmar resultados y finalizar el torneo?'
                      : '¿Confirmar resultados y lanzar la ronda ${t.currentRound + 1}?';
              if (!await confirmDialog(context, msg) || !mounted) return;
              await guard(
                  context, () => _repo.confirmAndNext(t, rounds, players));
              setState(() {
                viewRound = null;
                tab = last ? _Tab.standing : _Tab.tables;
              });
            },
            child: Text(last
                ? 'Confirmar y finalizar torneo'
                : 'Confirmar y lanzar ronda ${t.currentRound + 1}'),
          ),
        ]);
      default:
        children.add(const Text('Torneo finalizado. Standing final publicado.'));
    }
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.status == 'review' ? kGold : kLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children),
      ),
    );
  }

  // -------------------------------------------------------------- mesas
  Widget _resultChips(Points p, String pid, String? cur,
      void Function(String v) onPick) {
    final opts = p.usesPlacement ? ['W', '2', '3', 'L', 'D'] : ['W', 'D', 'L'];
    Color colorOf(String v) => switch (v) {
          'W' => kOk,
          'D' => kBlue,
          'L' => const Color(0xFF5C5472),
          _ => kGold,
        };
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final v in opts)
        ChoiceChip(
          label: Text(kResultLabels[v]!),
          selected: cur == v,
          selectedColor: colorOf(v),
          visualDensity: VisualDensity.compact,
          showCheckmark: false,
          onSelected: (_) => onPick(v),
        ),
    ]);
  }

  Widget _resultBadge(Points p, String? v) {
    if (v == null) return const Text('—', style: TextStyle(color: kMuted));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8)),
      child: Text('${kResultLabels[v]} · ${p.forResult(v)}p',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  /// mode: 'org' (editar), 'mine' (reportar), 'view' (solo ver)
  Widget _tableCard(Tournament t, RoundData r, TableData tb, String mode) {
    final key = 'r${r.n}-t${tb.t}';
    final rep = reports[key];
    final totals = {
      for (final s in computeStandings(
          confirmed.where((x) => x.n < r.n).toList(), players, t.pts))
        s.id: s.pts
    };
    final draft = drafts[key] ?? {};
    final rows = <Widget>[];
    for (var i = 0; i < tb.seats.length; i++) {
      final pid = tb.seats[i];
      final dropped = players[pid]?.dropped ?? false;
      Widget trailing;
      if (mode == 'org') {
        trailing = _resultChips(t.pts, pid, tb.res[pid], (v) {
          final tables = r.tables.map((x) => x.copy()).toList();
          final target = tables.firstWhere((x) => x.t == tb.t);
          applyPick(target.res, target.seats, pid, v, t.pts);
          guard(context, () => _repo.saveTables(code, r.n, tables));
        });
      } else if (mode == 'mine') {
        trailing = _resultChips(t.pts, pid, draft[pid], (v) {
          final d = Map<String, String>.from(draft);
          applyPick(d, tb.seats, pid, v, t.pts);
          setState(() => drafts[key] = d);
        });
      } else {
        trailing = _resultBadge(t.pts, tb.res[pid]);
      }
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
              constraints: const BoxConstraints(minWidth: 110),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nick(pid) + (dropped ? ' (drop)' : ''),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${totals[pid] ?? 0} pts',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  ]),
            ),
            trailing,
          ],
        ),
      ));
    }

    final footer = <Widget>[];
    if (mode == 'org') {
      footer.add(Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
            onPressed: () {
              final tables = r.tables.map((x) => x.copy()).toList();
              final target = tables.firstWhere((x) => x.t == tb.t);
              target.res
                ..clear()
                ..addAll({for (final p in target.seats) p: 'D'});
              guard(context, () => _repo.saveTables(code, r.n, tables));
            },
            child: const Text('Empate en mesa')),
        TextButton(
            onPressed: () {
              final tables = r.tables.map((x) => x.copy()).toList();
              tables.firstWhere((x) => x.t == tb.t).res.clear();
              guard(context, () => _repo.saveTables(code, r.n, tables));
            },
            child: const Text('Limpiar')),
      ]));
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
                onPressed: () {
                  final tables = r.tables.map((x) => x.copy()).toList();
                  tables.firstWhere((x) => x.t == tb.t).res
                    ..clear()
                    ..addAll(rep.res);
                  guard(context, () => _repo.saveTables(code, r.n, tables));
                },
                child: const Text('Aplicar')),
          ]),
        ));
      }
    }
    if (mode == 'mine') {
      final full = tb.seats.every((p) => draft[p] != null);
      footer.addAll([
        const SizedBox(height: 8),
        const Text(
            'Reporta el resultado de tu mesa. El organizador lo revisa antes de confirmar.',
            style: TextStyle(color: kMuted, fontSize: 12.5)),
        if (rep != null)
          Text('Reporte enviado por ${nick(rep.by)} ✓',
              style: const TextStyle(color: kOk, fontSize: 13)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: !full
              ? null
              : () => guard(context, () async {
                    await _repo.sendReport(code, r.n, tb.t, draft);
                    if (mounted) toast(context, 'Resultado enviado al organizador');
                  }),
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

  bool _sameRes(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  Widget _tables(Tournament t) {
    if (t.status == 'registration') {
      return const _Empty(
          'Las mesas aparecerán cuando el organizador comience el torneo.');
    }
    final n = viewRound ?? t.currentRound;
    final r = rounds[n];
    if (r == null) return const Center(child: CircularProgressIndicator());
    final editable = isOrg &&
        n == t.currentRound &&
        (t.status == 'round' || t.status == 'review');
    final rs = roundList;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rs.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final x in rs)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('R${x.n}'),
                  selected: x.n == n,
                  onSelected: (_) => setState(() => viewRound = x.n),
                ),
              ),
          ]),
        ),
      _SectionTitle('Ronda $n${r.confirmed ? ' · confirmada' : ''}'),
      if (isOrg && r.repeats > 0)
        Text(
            'Aviso: ${r.repeats} par(es) de jugadores repiten mesa (inevitable con estos jugadores/puntos).',
            style: const TextStyle(color: kMuted, fontSize: 12.5)),
      for (final tb in r.tables) _tableCard(t, r, tb, editable ? 'org' : 'view'),
      if (r.byes.isNotEmpty)
        Card(
          child: ListTile(
            title: const Text('Bye'),
            subtitle: Text(r.byes.map(nick).join(', ')),
            trailing: Text('+${t.pts.bye} pts'),
          ),
        ),
    ]);
  }

  Widget _myTable(Tournament t) {
    final me = myPid;
    if (me == null) {
      return const _Empty(
          'Estás viendo como espectador. Para jugar, vuelve atrás y usa "Unirme".');
    }
    final p = players[me]!;
    final dropBtn = (t.status != 'finished' && !p.dropped)
        ? TextButton(
            onPressed: () async {
              if (await confirmDialog(context,
                      '¿Abandonar el torneo? No tendrás mesa en las próximas rondas.',
                      ok: 'Abandonar') &&
                  mounted) {
                await guard(context, () => _repo.setDropped(code, me, true));
              }
            },
            child: const Text('Abandonar torneo'))
        : const SizedBox.shrink();

    if (t.status == 'registration') {
      return Column(children: [
        _Empty(
            '¡Inscrito como ${p.nick}! Esperando que el organizador comience. Inscritos: ${players.length}'),
        dropBtn,
      ]);
    }
    final st = confirmed.isEmpty
        ? null
        : _firstOrNull(computeStandings(confirmed, players, t.pts)
            .where((s) => s.id == me));
    final head = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _Stat('Tu posición', st == null ? '–' : '#${st.rank}'),
          _Stat('Puntos', '${st?.pts ?? 0}'),
          _Stat('OMW%', st == null ? '–' : fmtPct(st.omw)),
        ]),
      ),
    );
    final out = <Widget>[head];
    if (p.dropped) {
      out.add(const _Empty('Abandonaste el torneo.'));
    } else if (t.status == 'finished') {
      out.add(const _Empty('Torneo finalizado. Revisa el standing final.'));
    } else {
      final r = current;
      if (r != null) {
        if (r.byes.contains(me)) {
          out.add(_Empty('Bye en la ronda ${r.n}: recibes ${t.pts.bye} puntos.'));
        } else {
          final tb = _firstOrNull(r.tables.where((x) => x.seats.contains(me)));
          if (tb == null) {
            out.add(const _Empty(
                'No tienes mesa en esta ronda (te uniste tarde). Entrarás en la próxima.'));
          } else {
            final mode = !r.confirmed &&
                    (t.status == 'round' || t.status == 'review')
                ? 'mine'
                : 'view';
            out.addAll([
              _SectionTitle('Ronda ${r.n} · Mesa ${tb.t}'),
              _tableCard(t, r, tb, mode),
              const Text('El número de asiento indica el orden de turno (1 comienza).',
                  style: TextStyle(color: kMuted, fontSize: 12.5)),
            ]);
          }
        }
      }
      out.add(Center(child: dropBtn));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  // ----------------------------------------------------------- standing
  Widget _standing(Tournament t) {
    var rs = confirmed;
    var lbl = rs.isEmpty
        ? 'Sin rondas confirmadas aún'
        : 'Tras ${rs.length} ronda(s) confirmada(s)';
    final canPre = isOrg && t.status == 'review';
    if (canPre && prelim && current != null) {
      rs = [...rs, current!];
      lbl = 'Preliminar incluyendo ronda ${t.currentRound}';
    }
    final st = computeStandings(rs, players, t.pts);
    const hs = TextStyle(color: kMuted, fontSize: 11);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: _SectionTitle(
                t.status == 'finished' ? 'Standing final' : 'Standing general')),
        if (canPre)
          Row(children: [
            const Text('Incluir ronda actual', style: TextStyle(fontSize: 12)),
            Switch(value: prelim, onChanged: (v) => setState(() => prelim = v)),
          ]),
      ]),
      Text(
          '$lbl. Desempates: 1) Puntos · 2) OMW% · 3) MW% · 4) OOMW% (mínimo 33%, estilo MTR).',
          style: const TextStyle(color: kMuted, fontSize: 12.5)),
      const SizedBox(height: 8),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 14,
            horizontalMargin: 12,
            headingRowHeight: 36,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 44,
            columns: const [
              DataColumn(label: Text('#', style: hs)),
              DataColumn(label: Text('JUGADOR', style: hs)),
              DataColumn(label: Text('PTS', style: hs), numeric: true),
              DataColumn(label: Text('V-E-D', style: hs)),
              DataColumn(label: Text('OMW', style: hs), numeric: true),
              DataColumn(label: Text('MW', style: hs), numeric: true),
              DataColumn(label: Text('OOMW', style: hs), numeric: true),
            ],
            rows: [
              for (final s in st)
                DataRow(
                  color: WidgetStatePropertyAll(s.id == myPid
                      ? const Color(0x268B6CF0)
                      : Colors.transparent),
                  cells: [
                    DataCell(Text('${s.rank}',
                        style: TextStyle(
                            color: s.rank <= 3 && t.status == 'finished'
                                ? kGoldLight
                                : null,
                            fontWeight: FontWeight.w700))),
                    DataCell(Text(s.nick + (s.dropped ? ' (drop)' : ''),
                        style: TextStyle(
                            color: s.dropped ? kMuted : null,
                            fontWeight: FontWeight.w600))),
                    DataCell(Text('${s.pts}',
                        style: const TextStyle(
                            color: kGoldLight, fontWeight: FontWeight.w700))),
                    DataCell(Text(
                        '${s.w}-${s.d}-${s.l}${s.byes > 0 ? ' (+${s.byes}B)' : ''}')),
                    DataCell(Text(fmtPct(s.omw))),
                    DataCell(Text(fmtPct(s.mw))),
                    DataCell(Text(fmtPct(s.oomw))),
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
  }

  // ----------------------------------------------------------- jugadores
  final _addNick = TextEditingController();

  Widget _players(Tournament t) {
    final reg = t.status == 'registration';
    final ps = players.values.toList()
      ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    Future<void> add() async {
      final nk = _addNick.text.trim();
      if (nk.isEmpty) return;
      _addNick.clear();
      await guard(context, () => _repo.addManualPlayer(code, nk));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Agregar jugador manualmente',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
                'Para quien no tenga la app. ${reg ? '' : 'Entrará desde la próxima ronda.'}',
                style: const TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _addNick,
                      maxLength: 24,
                      decoration: const InputDecoration(
                          hintText: 'Nombre', counterText: ''),
                      onSubmitted: (_) => add())),
              const SizedBox(width: 8),
              FilledButton(onPressed: add, child: const Text('Agregar')),
            ]),
          ]),
        ),
      ),
      _SectionTitle('Inscritos (${ps.length})'),
      if (ps.isEmpty) const _Empty('Aún no hay jugadores.'),
      for (var i = 0; i < ps.length; i++)
        Card(
          child: ListTile(
            dense: true,
            title: Text('${i + 1}. ${ps[i].nick}'),
            subtitle: Text(
                '${ps[i].uid != null ? 'Con app' : 'Manual'}${ps[i].dropped ? ' · drop' : ''}'),
            trailing: reg
                ? TextButton(
                    onPressed: () async {
                      if (await confirmDialog(
                              context, '¿Quitar a ${ps[i].nick}?',
                              ok: 'Quitar') &&
                          mounted) {
                        await guard(
                            context, () => _repo.removePlayer(code, ps[i].id));
                      }
                    },
                    child: const Text('Quitar'))
                : TextButton(
                    onPressed: () => guard(context,
                        () => _repo.setDropped(code, ps[i].id, !ps[i].dropped)),
                    child: Text(ps[i].dropped ? 'Reincorporar' : 'Drop')),
          ),
        ),
    ]);
  }
}

NavigationDestination _destination(_Tab x) => switch (x) {
      _Tab.mine => const NavigationDestination(
          icon: Icon(Icons.chair_outlined), label: 'Mi mesa'),
      _Tab.tables => const NavigationDestination(
          icon: Icon(Icons.table_restaurant_outlined), label: 'Mesas'),
      _Tab.standing => const NavigationDestination(
          icon: Icon(Icons.leaderboard_outlined), label: 'Standing'),
      _Tab.players => const NavigationDestination(
          icon: Icon(Icons.group_outlined), label: 'Jugadores'),
      _Tab.settings =>
        const NavigationDestination(icon: Icon(Icons.tune), label: 'Ajustes'),
    };

T? _firstOrNull<T>(Iterable<T> it) => it.isEmpty ? null : it.first;

// ======================================================================
class _TimerBox extends StatefulWidget {
  final Tournament t;
  const _TimerBox({required this.t});
  @override
  State<_TimerBox> createState() => _TimerBoxState();
}

class _TimerBoxState extends State<_TimerBox> {
  late final Timer _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = widget.t.remainingMs();
    if (ms == null) return const SizedBox.shrink();
    final neg = ms < 0;
    final a = ms.abs();
    final txt =
        '${neg ? '+' : ''}${a ~/ 60000}:${((a % 60000) ~/ 1000).toString().padLeft(2, '0')}';
    final paused = widget.t.timerPaused != null;
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF150F27),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: neg ? kBad : kLine),
      ),
      child: Column(children: [
        Text(txt,
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: neg ? kBad : (paused ? kMuted : null))),
        Text(
            neg
                ? '¡Tiempo! Turnos extra'
                : paused
                    ? 'En pausa'
                    : 'Tiempo restante',
            style: const TextStyle(color: kMuted, fontSize: 11)),
      ]),
    );
  }
}

class _SettingsForm extends StatefulWidget {
  final Tournament t;
  const _SettingsForm({required this.t});
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final c = {
    'rounds': TextEditingController(text: '${widget.t.rounds}'),
    'min': TextEditingController(text: '${widget.t.roundMinutes}'),
    'win': TextEditingController(text: '${widget.t.pts.win}'),
    'draw': TextEditingController(text: '${widget.t.pts.draw}'),
    'loss': TextEditingController(text: '${widget.t.pts.loss}'),
    'p2': TextEditingController(text: '${widget.t.pts.p2}'),
    'p3': TextEditingController(text: '${widget.t.pts.p3}'),
    'bye': TextEditingController(text: '${widget.t.pts.bye}'),
  };

  num _n(String k, num d) => num.tryParse(c[k]!.text.trim()) ?? d;

  Widget _f(String k, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TextField(
              controller: c[k],
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: label)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Configuración', style: TextStyle(fontWeight: FontWeight.w700)),
          Row(children: [_f('rounds', 'Rondas'), _f('min', 'Minutos')]),
          Row(children: [_f('win', 'Victoria'), _f('draw', 'Empate'), _f('loss', 'Derrota')]),
          Row(children: [_f('p2', '2º lugar'), _f('p3', '3º lugar'), _f('bye', 'Bye')]),
          const Text(
              'Cambiar puntos recalcula todo el standing, incluidas rondas confirmadas.',
              style: TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => guard(context, () async {
              final minRounds = t.currentRound < 1 ? 1 : t.currentRound;
              await Repo.i.saveSettings(
                t.code,
                _n('rounds', t.rounds).toInt() < minRounds
                    ? minRounds
                    : _n('rounds', t.rounds).toInt(),
                _n('min', t.roundMinutes).toInt().abs(),
                Points(
                  win: _n('win', t.pts.win),
                  draw: _n('draw', t.pts.draw),
                  loss: _n('loss', t.pts.loss),
                  p2: _n('p2', t.pts.p2),
                  p3: _n('p3', t.pts.p3),
                  bye: _n('bye', t.pts.bye),
                ),
              );
              if (context.mounted) toast(context, 'Ajustes guardados');
            }),
            child: const Text('Guardar cambios'),
          ),
        ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: kMuted, fontSize: 12.5, letterSpacing: 1)),
      );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted)),
        ),
      );
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
        Text(value,
            style: const TextStyle(
                color: kGoldLight, fontSize: 24, fontWeight: FontWeight.w700)),
      ]);
}
