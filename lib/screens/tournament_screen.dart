import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/repo.dart';
import '../logic/swiss.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import '../widgets/player_dialog.dart';
import '../widgets/prep_editor.dart';
import '../widgets/table_card.dart';
import '../widgets/votes.dart';

class TournamentScreen extends StatefulWidget {
  final String code;
  final bool startOnMyTable;
  final bool startOnStanding;
  const TournamentScreen({
    super.key,
    required this.code,
    this.startOnMyTable = false,
    this.startOnStanding = false,
  });

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

enum _Tab { mine, tables, standing, players, settings }

class _TournamentScreenState extends State<TournamentScreen> {
  final _repo = Repo.i;
  final _subs = <StreamSubscription>[];
  StreamSubscription? _decksSub, _votesSub, _myDeckSub;
  bool _decksAll = false, _votesAll = false;

  Tournament? t;
  bool loaded = false;
  Map<String, PlayerData> players = {};
  Map<int, RoundData> rounds = {};
  Map<String, Report> reports = {};
  Map<String, DeckInfo> decks = {};
  DeckInfo? myDeck;
  List<Vote> votes = [];
  final Map<String, Map<String, String>> drafts = {};
  int? viewRound;
  bool prelim = false;
  bool busy = false;
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

  void _onErr(Object e) {
    if (mounted) toast(context, 'Error de conexión: $e');
  }

  @override
  void initState() {
    super.initState();
    if (widget.startOnMyTable) tab = _Tab.mine;
    if (widget.startOnStanding) tab = _Tab.standing;
    _subs.add(_repo.tournament(code).listen((v) {
      setState(() {
        t = v;
        loaded = true;
      });
      _syncPrivateSubs();
    }, onError: _onErr));
    _subs.add(_repo.players(code).listen((v) {
      setState(() => players = v);
      _syncPrivateSubs();
    }, onError: _onErr));
    _subs.add(_repo.rounds(code).listen((v) => setState(() => rounds = v),
        onError: _onErr));
    _subs.add(_repo.reports(code).listen((v) => setState(() => reports = v),
        onError: _onErr));
  }

  /// Barajas y votos son privados: se escucha la colección completa solo si
  /// las reglas lo permiten (organizador o visibilidad compartida).
  void _syncPrivateSubs() {
    final tt = t;
    if (tt == null) return;
    final wantDecks = tt.canSee(tt.shareDecks, isOrg);
    if (wantDecks != _decksAll || _decksSub == null) {
      _decksSub?.cancel();
      _decksAll = wantDecks;
      _decksSub = wantDecks
          ? _repo.decks(code).listen((v) => setState(() => decks = v),
              onError: (_) {})
          : null;
      if (!wantDecks) decks = {};
    }
    if (_myDeckSub == null && myPid != null) {
      _myDeckSub = _repo.myDeck(code, myPid!).listen(
          (v) => setState(() => myDeck = v),
          onError: (_) {});
    }
    final wantVotes = tt.canSee(tt.shareVotes, isOrg);
    if (wantVotes != _votesAll || _votesSub == null) {
      _votesSub?.cancel();
      _votesAll = wantVotes;
      _votesSub = wantVotes
          ? _repo.votes(code).listen((v) => setState(() => votes = v),
              onError: (_) {})
          : null;
      if (!wantVotes) votes = [];
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _decksSub?.cancel();
    _votesSub?.cancel();
    _myDeckSub?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    await guard(context, fn);
    if (mounted) setState(() => busy = false);
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
        ? [
            if (myPid != null) _Tab.mine,
            _Tab.tables,
            _Tab.standing,
            _Tab.players,
            _Tab.settings,
          ]
        : [_Tab.mine, _Tab.tables, _Tab.standing];
    if (tab == null || !tabs.contains(tab)) {
      tab = isOrg
          ? (t.status == 'registration' ? _Tab.players : _Tab.tables)
          : tabs.first;
    }

    final Widget body = switch (tab!) {
      _Tab.mine => _myTable(t),
      _Tab.tables => _tables(t),
      _Tab.standing => _standing(t),
      _Tab.players => _players(t),
      _Tab.settings => _SettingsForm(t: t),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(t.name, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              label: Text(isOrg
                  ? (myPid != null ? 'Organizador · jugando' : 'Organizador')
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
      'prep' => ('Preparando ronda ${t.currentRound}', kGold),
      'round' => ('Ronda ${t.currentRound}', kOk),
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
      if (t.status == 'round') TimerBox(t: t),
    ]);
  }

  // ------------------------------------------------------------ organizador
  Future<void> _back(Tournament t) async {
    final n = t.currentRound;
    final what = switch (t.status) {
      'round' =>
        'Volverás a la preparación de mesas de la ronda $n. Se borrarán los resultados, reportes y votos de esta ronda y se detendrá el reloj.',
      'prep' => n <= 1
          ? 'Se borrarán las mesas de la ronda 1 y volverás a la inscripción.'
          : 'Se borrarán las mesas de la ronda $n y volverás al ingreso de puntajes de la ronda ${n - 1}.',
      'finished' =>
        'El torneo volverá al ingreso de puntajes de la ronda $n.',
      _ => '',
    };
    if (what.isEmpty) return;
    if (!await confirmDialog(context, '⚠️ Volver atrás\n\n$what\n\n¿Continuar?',
            ok: 'Volver atrás') ||
        !mounted) {
      return;
    }
    await _run(() => _repo.goBack(t, rounds));
    setState(() => viewRound = null);
  }

  Widget _orgPanel(Tournament t) {
    final children = <Widget>[];
    final backBtn = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: busy ? null : () => _back(t),
        icon: const Icon(Icons.undo, size: 18),
        label: const Text('Volver atrás'),
        style: TextButton.styleFrom(foregroundColor: kBad),
      ),
    );
    switch (t.status) {
      case 'registration':
        final n = players.values.where((p) => !p.dropped).length;
        children.addAll([
          Text(
              'Comparte la clave $code para que los jugadores se inscriban. '
              'Sugerido para $n jugadores: ${suggestedRounds(n)} rondas.'),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: n < 3 || busy
                ? null
                : () async {
                    if (!await confirmDialog(context,
                            '¿Cerrar inscripciones y armar las mesas de la ronda 1 con $n jugadores? Podrás revisarlas y moverlas antes de empezar.',
                            ok: 'Armar mesas') ||
                        !mounted) {
                      return;
                    }
                    await _run(() => _repo.prepareFirstRound(t, players));
                    setState(() {
                      tab = _Tab.tables;
                      viewRound = null;
                    });
                  },
            child: Text(n < 3
                ? 'Necesitas al menos 3 jugadores'
                : 'Armar mesas de la ronda 1'),
          ),
        ]);
      case 'prep':
        final pr = current;
        final warns = pr == null ? <String>[] : prepWarnings(pr, players);
        children.addAll([
          Text('Preparación de la ronda ${t.currentRound}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
              'Revisa las mesas, muévelas si hace falta y empieza la ronda. El reloj parte al empezar.',
              style: TextStyle(color: kMuted, fontSize: 12.5)),
          for (final w in warns)
            Text('• $w', style: const TextStyle(color: kBad, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: pr == null || busy
                  ? null
                  : () async {
                      final qs = await editVoteQuestions(context, pr.voteQuestions);
                      if (qs == null || !mounted) return;
                      await _run(() => _repo.setVoteQuestions(code, pr.n, qs));
                    },
              icon: const Icon(Icons.how_to_vote, size: 18),
              label: Text(pr == null || pr.voteQuestions.isEmpty
                  ? 'Votación especial'
                  : 'Votación (${pr.voteQuestions.length})'),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (!await confirmDialog(context,
                              '¿Rearmar automáticamente las mesas de esta ronda? Se perderán los cambios manuales.',
                              ok: 'Rearmar') ||
                          !mounted) {
                        return;
                      }
                      await _run(() => _repo.rebuildRound(t, rounds, players));
                    },
              icon: const Icon(Icons.shuffle, size: 18),
              label: const Text('Rearmar mesas'),
            ),
          ]),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: pr == null || busy
                ? null
                : () async {
                    final msg = warns.isEmpty
                        ? '¿Empezar la ronda ${t.currentRound}? Se iniciará el reloj de ${t.roundMinutes} minutos.'
                        : 'Hay advertencias:\n${warns.map((w) => '• $w').join('\n')}\n\n¿Empezar la ronda igual?';
                    if (!await confirmDialog(context, msg, ok: 'Empezar ronda') ||
                        !mounted) {
                      return;
                    }
                    await _run(() => _repo.startRound(t));
                  },
            icon: const Icon(Icons.play_arrow),
            label: Text('Empezar ronda ${t.currentRound}'),
          ),
          backBtn,
        ]);
      case 'round':
        final rr = current;
        final total = rr?.tables.length ?? 0;
        final done = rr?.tables.where((x) => x.complete).length ?? 0;
        final all = rr != null && done == total;
        final last = t.currentRound >= t.rounds;
        final running = t.timerEnds != null || t.timerPaused != null;
        children.addAll([
          if (running)
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: () => _run(() => _repo.togglePause(t)),
                  icon: Icon(t.timerPaused != null ? Icons.play_arrow : Icons.pause),
                  label: Text(t.timerPaused != null ? 'Reanudar' : 'Pausar')),
              OutlinedButton(
                  onPressed: () => _run(() => _repo.addMinutes(t, -5)),
                  child: const Text('−5 min')),
              OutlinedButton(
                  onPressed: () => _run(() => _repo.addMinutes(t, 5)),
                  child: const Text('+5 min')),
            ]),
          const SizedBox(height: 8),
          Text('Resultados: $done de $total mesas',
              style: TextStyle(
                  color: all ? kOk : kMuted, fontWeight: FontWeight.w600)),
          const Text(
              'Puedes ingresar o corregir resultados durante la ronda y al terminar el tiempo.',
              style: TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: !all || busy
                ? null
                : () async {
                    final msg = last
                        ? '¿Enviar los puntos de la ronda ${t.currentRound} y finalizar el torneo?'
                        : '¿Enviar los puntos de la ronda ${t.currentRound}? Se actualizará el standing y se prepararán las mesas de la ronda ${t.currentRound + 1}.';
                    if (!await confirmDialog(context, msg, ok: 'Enviar puntos') ||
                        !mounted) {
                      return;
                    }
                    await _run(() => _repo.submitPoints(t, rounds, players));
                    setState(() {
                      viewRound = null;
                      tab = last ? _Tab.standing : _Tab.tables;
                    });
                  },
            icon: const Icon(Icons.send),
            label: Text(all
                ? (last ? 'Enviar puntos y finalizar' : 'Enviar puntos')
                : 'Faltan resultados por ingresar'),
          ),
          backBtn,
        ]);
      default:
        children.addAll([
          const Text('Torneo finalizado. El standing final está publicado.'),
          backBtn,
        ]);
    }
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.status == 'prep' ? kGold : kLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children),
      ),
    );
  }

  // ------------------------------------------------------------------ mesas
  Map<String, num> _totalsBefore(int n) => pointsBy(
      confirmed.where((x) => x.n < n).toList(), players, t!.pts);

  Widget _tableCard(Tournament t, RoundData r, TableData tb, TableMode mode) {
    final key = 'r${r.n}-t${tb.t}';
    return TableCard(
      t: t,
      round: r,
      table: tb,
      mode: mode,
      players: players,
      totals: _totalsBefore(r.n),
      decks: decks,
      report: reports[key],
      myPid: myPid,
      onResult: (pid, v) {
        final tables = r.tables.map((x) => x.copy()).toList();
        final target = tables.firstWhere((x) => x.t == tb.t);
        applyPick(target.res, target.seats, pid, v, t.pts);
        _run(() => _repo.saveResults(code, r.n, tables));
      },
      onDrawAll: () {
        final tables = r.tables.map((x) => x.copy()).toList();
        final target = tables.firstWhere((x) => x.t == tb.t);
        target.res
          ..clear()
          ..addAll({for (final p in target.seats) p: 'D'});
        _run(() => _repo.saveResults(code, r.n, tables));
      },
      onClear: () {
        final tables = r.tables.map((x) => x.copy()).toList();
        tables.firstWhere((x) => x.t == tb.t).res.clear();
        _run(() => _repo.saveResults(code, r.n, tables));
      },
      onApplyReport: () {
        final rep = reports[key];
        if (rep == null) return;
        final tables = r.tables.map((x) => x.copy()).toList();
        tables.firstWhere((x) => x.t == tb.t).res
          ..clear()
          ..addAll(rep.res);
        _run(() => _repo.saveResults(code, r.n, tables));
      },
      draft: drafts[key] ?? const {},
      onDraft: (pid, v) {
        final d = Map<String, String>.from(drafts[key] ?? const {});
        applyPick(d, tb.seats, pid, v, t.pts);
        setState(() => drafts[key] = d);
      },
      onSendReport: () => _run(() async {
        await _repo.sendReport(code, r.n, tb.t, drafts[key] ?? const {});
        if (mounted) toast(context, 'Resultado enviado al organizador');
      }),
    );
  }

  Widget _roundSelector(int n) {
    final rs = roundList;
    if (rs.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
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
    );
  }

  Widget _tables(Tournament t) {
    if (t.status == 'registration') {
      return const EmptyCard(
          'Las mesas aparecerán cuando el organizador cierre las inscripciones.');
    }
    final n = viewRound ?? t.currentRound;
    final r = rounds[n];
    if (r == null) return const Center(child: CircularProgressIndicator());
    final isCurrent = n == t.currentRound;
    final out = <Widget>[_roundSelector(n)];

    if (isCurrent && t.status == 'prep') {
      out.add(SectionTitle('Ronda $n · preparación'));
      if (isOrg) {
        out.add(PrepEditor(
          round: r,
          players: players,
          points: _totalsBefore(n),
          onChanged: (tables, byes) =>
              _run(() => _repo.saveRoundTables(t, rounds, r, tables, byes)),
        ));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
      }
      out.add(const Text(
          'Mesas provisionales: el organizador puede cambiarlas antes de empezar.',
          style: TextStyle(color: kMuted, fontSize: 12.5)));
    } else {
      out.add(SectionTitle('Ronda $n${r.confirmed ? ' · confirmada' : ''}'));
    }
    final editable = isOrg && isCurrent && t.status == 'round';
    for (final tb in r.tables) {
      out.add(_tableCard(t, r, tb, editable ? TableMode.org : TableMode.view));
    }
    if (r.byes.isNotEmpty) {
      out.add(Card(
        child: ListTile(
          title: const Text('Bye'),
          subtitle: Text(r.byes.map(nick).join(', ')),
          trailing: Text('+${t.pts.bye} pts'),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  // ---------------------------------------------------------------- mi mesa
  Future<void> _editMyDeck(Tournament t) async {
    final f = await playerDialog(context, t,
        title: 'Mis datos',
        nick: players[myPid]?.nick ?? '',
        deck: myDeck ?? const DeckInfo());
    if (f == null || !mounted) return;
    await _run(() => _repo.join(code, f.nick, deck: f.deck).then((_) {}));
  }

  Widget _myTable(Tournament t) {
    final me = myPid;
    if (me == null) {
      return const EmptyCard(
          'Estás viendo como espectador. Para jugar, vuelve atrás y usa "Unirme".');
    }
    final p = players[me]!;
    final out = <Widget>[];

    final st = confirmed.isEmpty
        ? null
        : _firstOrNull(computeStandings(confirmed, players, t.pts)
            .where((s) => s.id == me));
    out.add(Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Stat('Tu posición', st == null ? '–' : '#${st.rank}'),
          Stat('Puntos', '${st?.pts ?? 0}'),
          Stat('OMW%', st == null ? '–' : fmtPct(st.omw)),
        ]),
      ),
    ));

    // Datos del jugador y baraja
    out.add(Card(
      child: ListTile(
        leading: const Icon(Icons.style_outlined, color: kGold),
        title: Text(p.nick),
        subtitle: Text(myDeck == null || myDeck!.isEmpty
            ? (t.asksDeck ? 'Sin datos de baraja' : 'Toca para editar tu nick')
            : [myDeck!.commander, myDeck!.listUrl]
                .where((x) => x.isNotEmpty)
                .join('\n')),
        trailing: const Icon(Icons.edit),
        onTap: t.status == 'finished' ? null : () => _editMyDeck(t),
      ),
    ));

    if (p.dropped) {
      out.add(const EmptyCard('Abandonaste el torneo.'));
    } else if (t.status == 'registration') {
      out.add(EmptyCard(
          'Inscrito. Esperando que el organizador arme las mesas. Inscritos: ${players.length}'));
    } else if (t.status == 'finished') {
      out.add(const EmptyCard('Torneo finalizado. Revisa el standing final.'));
    } else {
      final r = current;
      if (r != null) {
        final tb = r.tableOf(me);
        if (r.byes.contains(me)) {
          out.add(EmptyCard(
              'Bye en la ronda ${r.n}: recibes ${t.pts.bye} puntos.'));
        } else if (tb == null) {
          out.add(EmptyCard(t.status == 'prep'
              ? 'El organizador está armando las mesas de la ronda ${r.n}.'
              : 'No tienes mesa en esta ronda. Entrarás en la próxima.'));
        } else if (t.status == 'prep') {
          out.add(SectionTitle('Ronda ${r.n} · Mesa ${tb.t} (provisional)'));
          out.add(_tableCard(t, r, tb, TableMode.view));
          out.add(const Text(
              'El organizador aún puede cambiar las mesas antes de empezar.',
              style: TextStyle(color: kMuted, fontSize: 12.5)));
        } else {
          out.add(SectionTitle('Ronda ${r.n} · Mesa ${tb.t}'));
          out.add(_tableCard(t, r, tb, isOrg ? TableMode.org : TableMode.mine));
          out.add(const Text(
              'El número de asiento indica el orden de turno (1 comienza).',
              style: TextStyle(color: kMuted, fontSize: 12.5)));
          if (r.voteQuestions.isNotEmpty) {
            out.add(PlayerVoteCard(
              code: code,
              round: r,
              opponents: tb.seats.where((x) => x != me).toList(),
              nick: nick,
            ));
          }
        }
      }
      out.add(Center(
        child: TextButton(
            onPressed: () async {
              if (await confirmDialog(context,
                      '¿Abandonar el torneo? No tendrás mesa en las próximas rondas.',
                      ok: 'Abandonar') &&
                  mounted) {
                await _run(() => _repo.setDropped(code, me, true));
              }
            },
            child: const Text('Abandonar torneo')),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  // ---------------------------------------------------------------- standing
  Widget _standing(Tournament t) {
    var rs = confirmed;
    var lbl = rs.isEmpty
        ? 'Sin rondas confirmadas aún'
        : 'Tras ${rs.length} ronda(s) confirmada(s)';
    final canPre = isOrg && t.status == 'round';
    if (canPre && prelim && current != null) {
      rs = [...rs, current!];
      lbl = 'Preliminar incluyendo la ronda ${t.currentRound}';
    }
    final st = computeStandings(rs, players, t.pts);
    const hs = TextStyle(color: kMuted, fontSize: 11);
    final showDecks = decks.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        t.status == 'finished' ? 'Standing final' : 'Standing general',
        trailing: canPre
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Incluir ronda actual',
                    style: TextStyle(fontSize: 12)),
                Switch(
                    value: prelim, onChanged: (v) => setState(() => prelim = v)),
              ])
            : null,
      ),
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
            dataRowMaxHeight: 48,
            columns: [
              const DataColumn(label: Text('#', style: hs)),
              const DataColumn(label: Text('JUGADOR', style: hs)),
              if (showDecks) const DataColumn(label: Text('BARAJA', style: hs)),
              const DataColumn(label: Text('PTS', style: hs), numeric: true),
              const DataColumn(label: Text('V-E-D', style: hs)),
              const DataColumn(label: Text('OMW', style: hs), numeric: true),
              const DataColumn(label: Text('MW', style: hs), numeric: true),
              const DataColumn(label: Text('OOMW', style: hs), numeric: true),
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
                    if (showDecks) DataCell(_deckCell(decks[s.id])),
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
      if (isOrg && t.shareDecks != ShareMode.always && showDecks)
        Text(
            t.shareDecks == ShareMode.end
                ? 'Las barajas las ves tú; los jugadores las verán al finalizar.'
                : 'Las barajas solo las ves tú (cámbialo en Ajustes).',
            style: const TextStyle(color: kMuted, fontSize: 12)),
      VoteResults(votes: votes, rounds: roundList, nick: nick),
      if (isOrg && t.shareVotes != ShareMode.always && votes.isNotEmpty)
        Text(
            t.shareVotes == ShareMode.end
                ? 'Los votos los ves tú; los jugadores los verán al finalizar.'
                : 'Los votos solo los ves tú (cámbialo en Ajustes).',
            style: const TextStyle(color: kMuted, fontSize: 12)),
    ]);
  }

  Widget _deckCell(DeckInfo? d) {
    if (d == null || d.isEmpty) return const Text('—', style: TextStyle(color: kMuted));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(d.commander.isEmpty ? 'Lista' : d.commander,
            overflow: TextOverflow.ellipsis),
      ),
      if (d.listUrl.isNotEmpty)
        IconButton(
          tooltip: 'Abrir lista',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.open_in_new, size: 16),
          onPressed: () async {
            final u = Uri.tryParse(d.listUrl);
            if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
          },
        ),
    ]);
  }

  // ---------------------------------------------------------------- jugadores
  Widget _players(Tournament t) {
    final reg = t.status == 'registration';
    final ps = players.values.toList()
      ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));

    Future<void> addManual() async {
      final f = await playerDialog(context, t,
          title: 'Agregar jugador', okLabel: 'Agregar');
      if (f == null || !mounted) return;
      await _run(() => _repo.addManualPlayer(code, f.nick, deck: f.deck));
    }

    Future<void> joinAsOrg() async {
      final me = await _repo.me().first;
      if (!mounted) return;
      final f = await playerDialog(context, t,
          title: 'Jugar en mi torneo',
          okLabel: 'Inscribirme',
          nick: '${me['nick'] ?? ''}');
      if (f == null || !mounted) return;
      await _run(() async {
        final msg = await _repo.join(code, f.nick, deck: f.deck);
        if (mounted && msg != null) toast(context, msg);
      });
    }

    Future<void> editPlayer(PlayerData p) async {
      final f = await playerDialog(context, t,
          title: 'Editar jugador', nick: p.nick, deck: decks[p.id] ?? const DeckInfo());
      if (f == null || !mounted) return;
      await _run(() async {
        await _repo.saveDeck(code, p.id, f.deck);
        if (f.nick != p.nick) {
          await _repo.renamePlayer(code, p.id, f.nick);
        }
      });
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: busy ? null : addManual,
            icon: const Icon(Icons.person_add),
            label: const Text('Agregar jugador')),
        if (myPid == null && t.status != 'finished')
          OutlinedButton.icon(
              onPressed: busy ? null : joinAsOrg,
              icon: const Icon(Icons.sports_esports),
              label: const Text('Jugar en mi torneo')),
      ]),
      if (!reg)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
              'Los jugadores que se agreguen ahora entran desde la próxima preparación de mesas.',
              style: TextStyle(color: kMuted, fontSize: 12.5)),
        ),
      SectionTitle('Inscritos (${ps.length})'),
      if (ps.isEmpty) const EmptyCard('Aún no hay jugadores.'),
      for (var i = 0; i < ps.length; i++)
        Card(
          child: ListTile(
            dense: true,
            onTap: () => editPlayer(ps[i]),
            title: Text('${i + 1}. ${ps[i].nick}${ps[i].id == uid ? ' (tú)' : ''}'),
            subtitle: Text([
              ps[i].uid != null ? 'Con app' : 'Manual',
              if (ps[i].dropped) 'drop',
              if ((decks[ps[i].id]?.commander ?? '').isNotEmpty)
                decks[ps[i].id]!.commander,
            ].join(' · ')),
            trailing: reg
                ? TextButton(
                    onPressed: () async {
                      if (await confirmDialog(
                              context, '¿Quitar a ${ps[i].nick}?',
                              ok: 'Quitar') &&
                          mounted) {
                        await _run(() => _repo.removePlayer(code, ps[i].id));
                      }
                    },
                    child: const Text('Quitar'))
                : TextButton(
                    onPressed: () => _run(() =>
                        _repo.setDropped(code, ps[i].id, !ps[i].dropped)),
                    child: Text(ps[i].dropped ? 'Reincorporar' : 'Drop')),
          ),
        ),
    ]);
  }
}

T? _firstOrNull<T>(Iterable<T> it) => it.isEmpty ? null : it.first;

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

// ======================================================================
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
  late FieldMode cmd = widget.t.commanderField;
  late FieldMode list = widget.t.deckListField;
  late ShareMode shareDecks = widget.t.shareDecks;
  late ShareMode shareVotes = widget.t.shareVotes;

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
          const SizedBox(height: 12),
          FieldModePicker(
              label: 'Baraja / Comandante',
              value: cmd,
              onChanged: (v) => setState(() => cmd = v)),
          FieldModePicker(
              label: 'Lista de la baraja (URL)',
              value: list,
              onChanged: (v) => setState(() => list = v)),
          ShareModePicker(
              label: 'Quién ve las barajas',
              value: shareDecks,
              onChanged: (v) => setState(() => shareDecks = v)),
          ShareModePicker(
              label: 'Quién ve los votos',
              value: shareVotes,
              onChanged: (v) => setState(() => shareVotes = v)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => guard(context, () async {
              final minRounds = t.currentRound < 1 ? 1 : t.currentRound;
              final r = _n('rounds', t.rounds).toInt();
              await Repo.i.saveSettings(
                t,
                rounds: r < minRounds ? minRounds : r,
                minutes: _n('min', t.roundMinutes).toInt().abs(),
                pts: Points(
                  win: _n('win', t.pts.win),
                  draw: _n('draw', t.pts.draw),
                  loss: _n('loss', t.pts.loss),
                  p2: _n('p2', t.pts.p2),
                  p3: _n('p3', t.pts.p3),
                  bye: _n('bye', t.pts.bye),
                ),
                commanderField: cmd,
                deckListField: list,
                shareDecks: shareDecks,
                shareVotes: shareVotes,
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

/// Selector Desactivado / Opcional / Obligatorio.
class FieldModePicker extends StatelessWidget {
  final String label;
  final FieldMode value;
  final ValueChanged<FieldMode> onChanged;
  const FieldModePicker(
      {super.key, required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 4),
          SegmentedButton<FieldMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: FieldMode.off, label: Text('No pedir')),
              ButtonSegment(value: FieldMode.optional, label: Text('Opcional')),
              ButtonSegment(value: FieldMode.required, label: Text('Obligatorio')),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ]),
      );
}

/// Selector Solo organizador / Siempre / Al finalizar.
class ShareModePicker extends StatelessWidget {
  final String label;
  final ShareMode value;
  final ValueChanged<ShareMode> onChanged;
  const ShareModePicker(
      {super.key, required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 4),
          SegmentedButton<ShareMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ShareMode.never, label: Text('Solo yo')),
              ButtonSegment(value: ShareMode.end, label: Text('Al finalizar')),
              ButtonSegment(value: ShareMode.always, label: Text('Todos')),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ]),
      );
}
