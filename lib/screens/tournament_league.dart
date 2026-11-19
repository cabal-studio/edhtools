part of 'tournament_screen.dart';

/// Pantallas específicas de la Liga (rondas en distintos días, inscripción
/// por ronda con su propia clave, logros y desempates configurables).
extension _LeagueUI on _TournamentScreenState {
  bool get _seeAllClaims => t != null && t!.canSee(t!.shareAchievements, isOrg);

  /// Standing de liga con las rondas dadas.
  List<LeagueStanding> _leagueStandings(List<RoundData> rs) {
    final tt = t!;
    return computeLeagueStandings(
      rounds: rs,
      players: players,
      pts: tt.pts,
      achievements: tt.achievementsOn ? tt.achievements : const {},
      // Sin acceso a todos los logros se usan los puntajes guardados.
      claims: _seeAllClaims ? claims : null,
      tiebreakers: tt.tiebreakers,
      maxScores: tt.maxScores,
    );
  }

  Map<String, num> _leagueTotalsBefore(int n) => {
        for (final s in _leagueStandings(
            confirmed.where((x) => x.n < n).toList()))
          s.id: s.total
      };

  // ------------------------------------------------------------ organizador
  Widget _leaguePanel(Tournament t) {
    final n = t.currentRound;
    final r = current;
    final entered = entries[n] ?? const <String>{};
    final children = <Widget>[];
    Widget back() => Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : () => _back(t),
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Volver atrás'),
            style: TextButton.styleFrom(foregroundColor: kBad),
          ),
        );

    switch (t.status) {
      case 'between':
        children.addAll([
          Text(n == 0
              ? 'Liga creada. Comparte la clave $code para que los jugadores se unan, y abre la primera ronda cuando quieras.'
              : 'Ronda $n terminada. Abre la siguiente ronda cuando corresponda (puede ser otro día).'),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy ? null : () => _openRoundDialog(t),
            icon: const Icon(Icons.add),
            label: Text('Abrir ronda ${n + 1}'),
          ),
          if (n > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (await confirmDialog(context,
                                '¿Finalizar la liga? El standing quedará como final.',
                                ok: 'Finalizar') &&
                            mounted) {
                          await _run(() => _repo.finishLeague(t));
                        }
                      },
                child: const Text('Finalizar liga'),
              ),
            ),
          if (n > 0) back(),
        ]);
      case 'registration':
        children.addAll([
          Text('Inscripción de la ronda $n',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (r?.key != null) _keyBox('Clave de la ronda', r!.key!),
          const SizedBox(height: 6),
          Text(
              '${entered.length} inscrito(s). Los jugadores entran con la clave de la ronda; también puedes inscribirlos tú en la pestaña Mesas.',
              style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 8),
          if (r != null) _pairingPicker(t, r),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: entered.length < 3 || busy
                ? null
                : () => _run(() => _repo.buildLeagueTables(
                    t, rounds, players, entered, claims)),
            icon: const Icon(Icons.table_restaurant),
            label: Text(entered.length < 3
                ? 'Se necesitan al menos 3 inscritos'
                : 'Cerrar inscripción y armar mesas'),
          ),
          back(),
        ]);
      case 'prep':
        final warns = r == null ? <String>[] : _leaguePrepWarnings(r, entered);
        children.addAll([
          Text('Preparación de la ronda $n',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (r?.key != null) ...[
            const SizedBox(height: 6),
            _keyBox('Clave de la ronda', r!.key!),
          ],
          for (final w in warns)
            Text('• $w', style: const TextStyle(color: kBad, fontSize: 13)),
          const SizedBox(height: 8),
          if (r != null) _pairingPicker(t, r),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: r == null || busy
                  ? null
                  : () async {
                      final qs = await editVoteQuestions(context, r.voteQuestions,
                          owner: t.ownerId);
                      if (qs == null || !mounted) return;
                      await _run(() => _repo.setVoteQuestions(code, r.n, qs, owner: t.ownerId));
                    },
              icon: const Icon(Icons.how_to_vote, size: 18),
              label: Text(r == null || r.voteQuestions.isEmpty
                  ? 'Votación especial'
                  : 'Votación (${r.voteQuestions.length})'),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (!await confirmDialog(context,
                              '¿Rearmar las mesas con los inscritos actuales? Se perderán los cambios manuales.',
                              ok: 'Rearmar') ||
                          !mounted) {
                        return;
                      }
                      await _run(() => _repo.buildLeagueTables(
                          t, rounds, players, entered, claims));
                    },
              icon: const Icon(Icons.shuffle, size: 18),
              label: const Text('Rearmar mesas'),
            ),
          ]),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: r == null || busy
                ? null
                : () async {
                    final msg = warns.isEmpty
                        ? '¿Empezar la ronda $n? Se iniciará el reloj de ${t.roundMinutes} minutos${t.achievementsOn ? ' y se entregarán los logros automáticos' : ''}.'
                        : 'Hay advertencias:\n${warns.map((w) => '• $w').join('\n')}\n\n¿Empezar la ronda igual?';
                    if (!await confirmDialog(context, msg, ok: 'Empezar ronda') ||
                        !mounted) {
                      return;
                    }
                    await _run(() => _repo.startRound(t, round: r));
                  },
            icon: const Icon(Icons.play_arrow),
            label: Text('Empezar ronda $n'),
          ),
          back(),
        ]);
      case 'round':
        final total = r?.tables.length ?? 0;
        final done = r?.tables.where((x) => x.complete).length ?? 0;
        final all = r != null && done == total;
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
          if (t.achievementsOn)
            Text(
                'Logros de la ronda: ${claims.where((c) => c.round == n).length}. Puedes modificarlos en la pestaña Mesas.',
                style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: !all || busy
                ? null
                : () async {
                    if (!await confirmDialog(context,
                            '¿Enviar los puntos de la ronda $n? Se actualizará el standing de la liga.',
                            ok: 'Enviar puntos') ||
                        !mounted) {
                      return;
                    }
                    await _run(() =>
                        _repo.submitPoints(t, rounds, players, claims: claims));
                    _set(() {
                      viewRound = null;
                      tab = _Tab.standing;
                    });
                  },
            icon: const Icon(Icons.send),
            label: Text(all ? 'Enviar puntos' : 'Faltan resultados por ingresar'),
          ),
          back(),
        ]);
      default:
        children.addAll([
          const Text('Liga finalizada. El standing final está publicado.'),
          back(),
        ]);
    }
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: t.status == 'prep' || t.status == 'registration' ? kGold : kLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  List<String> _leaguePrepWarnings(RoundData r, Set<String> entered) {
    final out = <String>[];
    final seated = r.seated;
    final missing = entered
        .where((p) => !seated.contains(p) && !(players[p]?.dropped ?? false))
        .length;
    if (missing > 0) out.add('$missing inscrito(s) sin mesa');
    final small = r.tables.where((x) => x.seats.length < 3).length;
    if (small > 0) out.add('$small mesa(s) con menos de 3 jugadores');
    return out;
  }

  Widget _keyBox(String label, String key) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: key));
          if (mounted) toast(context, 'Clave copiada: $key');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kOk.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kOk.withValues(alpha: .5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${label.toUpperCase()} ',
                style: const TextStyle(color: kMuted, fontSize: 11)),
            Text(key,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 22,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                    color: kOk)),
            const SizedBox(width: 6),
            const Icon(Icons.copy, size: 16, color: kMuted),
          ]),
        ),
      );

  Widget _pairingPicker(Tournament t, RoundData r) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cómo armar las mesas',
              style: TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 4),
          SegmentedButton<PairingMode>(
            showSelectedIcon: false,
            segments: [
              for (final m in PairingMode.values)
                ButtonSegment(value: m, label: Text(switch (m) {
                  PairingMode.random => 'Aleatorio',
                  PairingMode.leaders => 'Con líderes',
                  PairingMode.swiss => 'Suizo',
                })),
            ],
            selected: {pairingFrom(r.pairing)},
            onSelectionChanged: (s) =>
                _run(() => _repo.setRoundPairing(code, r.n, s.first)),
          ),
          if (pairingFrom(r.pairing) == PairingMode.leaders)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'Los 3 primeros del standing quedan en mesas distintas: líder 1 en la mesa 3, líder 2 en la mesa 2 y líder 3 en la mesa 1.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
            ),
          const SizedBox(height: 8),
        ],
      );

  Future<void> _openRoundDialog(Tournament t) async {
    var mode = PairingMode.random;
    DateTime date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text('Abrir ronda ${t.currentRound + 1}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Se generará una clave para esta ronda. Los jugadores la usan para inscribirse.',
                style: TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(
                  'Fecha: ${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}'),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final p = await showDatePicker(
                    context: d,
                    initialDate: date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2100));
                if (p != null) setD(() => date = p);
              },
            ),
            const SizedBox(height: 8),
            const Text('Mesas', style: TextStyle(color: kMuted, fontSize: 12.5)),
            for (final m in PairingMode.values)
              RadioListTile<PairingMode>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: m,
                groupValue: mode,
                title: Text(kPairingLabels[m]!),
                onChanged: (v) => setD(() => mode = v ?? mode),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Abrir ronda')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final key = await _repo.openLeagueRound(t,
          pairing: mode, date: date.millisecondsSinceEpoch);
      if (mounted) toast(context, 'Ronda abierta · clave $key');
    });
    _set(() => tab = _Tab.tables);
  }

  /// Mesas → en inscripción: lista de inscritos de la ronda.
  Widget? _leagueTablesHead(Tournament t) {
    final n = t.currentRound;
    if (n == 0) {
      return const EmptyCard('Aún no hay rondas. El organizador abrirá la primera.');
    }
    if (t.status != 'registration' || viewRound != null && viewRound != n) {
      return null;
    }
    final entered = entries[n] ?? const <String>{};
    final active = players.values.where((p) => !p.dropped).toList()
      ..sort((a, b) => a.nick.toLowerCase().compareTo(b.nick.toLowerCase()));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _roundSelector(n),
      SectionTitle('Ronda $n · inscritos (${entered.length})'),
      if (!isOrg)
        const Text('El organizador armará las mesas al cerrar la inscripción.',
            style: TextStyle(color: kMuted, fontSize: 12.5)),
      if (isOrg)
        const Text(
            'Marca a los jugadores de la liga que juegan esta ronda. Para alguien nuevo, usa "Agregar jugador" en la pestaña Jugadores.',
            style: TextStyle(color: kMuted, fontSize: 12.5)),
      for (final p in active)
        if (isOrg || entered.contains(p.id))
          Card(
            child: CheckboxListTile(
              dense: true,
              value: entered.contains(p.id),
              title: Text(p.nick),
              subtitle: Text(p.uid != null ? (p.google ? 'Google' : 'App') : 'Manual'),
              onChanged: !isOrg
                  ? null
                  : (v) => _run(() => v == true
                      ? _repo.addEntry(code, n, p.id)
                      : _repo.removeEntry(code, n, p.id)),
            ),
          ),
    ]);
  }

  // ---------------------------------------------------------------- jugador
  List<Widget> _leagueMine(Tournament t, String me) {
    final out = <Widget>[];
    final n = t.currentRound;
    final r = current;
    final entered = (entries[n] ?? const <String>{}).contains(me);
    switch (t.status) {
      case 'between':
        out.add(EmptyCard(n == 0
            ? 'Estás en la liga. Cuando el organizador abra una ronda podrás inscribirte con su clave o desde aquí.'
            : 'Ronda $n terminada. Espera a que el organizador abra la siguiente.'));
      case 'registration' || 'prep':
        if (!entered) {
          out.add(EmptyCard(
            'La ronda $n está abierta. ¿Juegas esta ronda?',
            action: FilledButton.icon(
              onPressed: busy ? null : () => _run(() => _repo.addEntry(code, n, me)),
              icon: const Icon(Icons.how_to_reg),
              label: Text('Inscribirme en la ronda $n'),
            ),
          ));
        } else {
          final tb = r?.tableOf(me);
          if (t.status == 'prep' && tb != null && r != null) {
            out.add(SectionTitle('Ronda $n · Mesa ${tb.t} (provisional)'));
            out.add(_tableCard(t, r, tb, TableMode.view));
          } else {
            out.add(EmptyCard(
              'Inscrito en la ronda $n ✓. El organizador armará las mesas.',
              action: TextButton(
                onPressed: busy ? null : () => _run(() => _repo.removeEntry(code, n, me)),
                child: const Text('No juego esta ronda'),
              ),
            ));
          }
        }
      case 'round':
        if (r == null) break;
        final tb = r.tableOf(me);
        if (r.byes.contains(me)) {
          out.add(EmptyCard('Bye en la ronda ${r.n}: recibes ${t.pts.bye} puntos.'));
        } else if (tb == null) {
          out.add(const EmptyCard('No juegas esta ronda.'));
        } else {
          out.add(SectionTitle('Ronda ${r.n} · Mesa ${tb.t}'));
          out.add(_tableCard(t, r, tb, isOrg ? TableMode.org : TableMode.mine));
          out.add(const Text(
              'El número de asiento indica el orden de turno (1 comienza).',
              style: TextStyle(color: kMuted, fontSize: 12.5)));
          if (t.achievementsOn && me == uid) {
            out.add(ClaimCard(t: t, round: r, pid: me, myClaims: myClaims));
          }
          if (r.voteQuestions.isNotEmpty) {
            out.add(PlayerVoteCard(
              code: code,
              round: r,
              opponents: tb.seats.where((x) => x != me).toList(),
              nick: nick,
            ));
          }
        }
      default:
        out.add(const EmptyCard('Liga finalizada. Revisa el standing final.'));
    }
    return out;
  }

  // --------------------------------------------------------------- standing
  Widget _leagueStanding(Tournament t) {
    var rs = confirmed;
    var lbl = rs.isEmpty
        ? 'Sin rondas confirmadas aún'
        : 'Tras ${rs.length} ronda(s)';
    final canPre = isOrg && t.status == 'round';
    if (canPre && prelim && current != null) {
      rs = [...rs, current!];
      lbl = 'Preliminar incluyendo la ronda ${t.currentRound}';
    }
    final st = _leagueStandings(rs);
    const hs = TextStyle(color: kMuted, fontSize: 11);
    final tbs = t.tiebreakers;
    String fmt(String k, LeagueStanding s) => switch (k) {
          'omw' => fmtPct(s.omw),
          'mw' => fmtPct(s.mw),
          'oomw' => fmtPct(s.oomw),
          _ => '${s.tiebreak(k)}',
        };
    String head(String k) => switch (k) {
          'omw' => 'OMW',
          'mw' => 'MW',
          'oomw' => 'OOMW',
          'wins' => 'VICT.',
          _ => (t.achievements[k.substring(4)]?.name ?? 'Logro').toUpperCase(),
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        t.status == 'finished' ? 'Standing final de la liga' : 'Standing de la liga',
        trailing: canPre
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Incluir ronda actual', style: TextStyle(fontSize: 12)),
                Switch(value: prelim, onChanged: (v) => _set(() => prelim = v)),
              ])
            : null,
      ),
      Text(
          '$lbl. ${t.maxScores > 0 ? 'Cuentan los ${t.maxScores} mejores puntajes de ronda. ' : ''}'
          'Desempates: ${tbs.isEmpty ? 'ninguno' : tbs.map((k) => tiebreakLabel(k, t.achievements)).join(' · ')}.',
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
              const DataColumn(label: Text('PTS', style: hs), numeric: true),
              if (t.maxScores > 0)
                const DataColumn(label: Text('TOTAL', style: hs), numeric: true),
              const DataColumn(label: Text('RONDAS', style: hs), numeric: true),
              for (final k in tbs) DataColumn(label: Text(head(k), style: hs), numeric: true),
            ],
            rows: [
              for (final s in st)
                if (s.roundsPlayed > 0 || rs.isEmpty)
                  DataRow(
                    color: WidgetStatePropertyAll(s.id == myPid
                        ? const Color(0x268B6CF0)
                        : Colors.transparent),
                    cells: [
                      DataCell(Text('${s.rank}',
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text(s.nick + (s.dropped ? ' (drop)' : ''),
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text('${s.total}',
                          style: const TextStyle(
                              color: kGoldLight, fontWeight: FontWeight.w700))),
                      if (t.maxScores > 0) DataCell(Text('${s.allPoints}')),
                      DataCell(Text('${s.roundsPlayed}')),
                      for (final k in tbs) DataCell(Text(fmt(k, s))),
                    ],
                  ),
            ],
          ),
        ),
      ),
      if (t.achievementsOn && _seeAllClaims)
        AchievementsSummary(t: t, standings: st, rounds: rs, claims: claims),
      if (t.achievementsOn && isOrg && t.shareAchievements != ShareMode.always)
        Text(
            t.shareAchievements == ShareMode.end
                ? 'El detalle de logros lo ves tú; los jugadores lo verán al finalizar.'
                : 'El detalle de logros solo lo ves tú (cámbialo en Ajustes).',
            style: const TextStyle(color: kMuted, fontSize: 12)),
      VoteResults(votes: votes, rounds: roundList, nick: nick),
    ]);
  }
}

// ======================================================================
/// Ajustes de una liga.
class _LeagueSettingsForm extends StatefulWidget {
  final Tournament t;
  final Map<int, RoundData> rounds;
  final List<Claim> claims;
  const _LeagueSettingsForm(
      {required this.t, required this.rounds, required this.claims});
  @override
  State<_LeagueSettingsForm> createState() => _LeagueSettingsFormState();
}

class _LeagueSettingsFormState extends State<_LeagueSettingsForm> {
  late final c = {
    'min': TextEditingController(text: '${widget.t.roundMinutes}'),
    'win': TextEditingController(text: '${widget.t.pts.win}'),
    'draw': TextEditingController(text: '${widget.t.pts.draw}'),
    'loss': TextEditingController(text: '${widget.t.pts.loss}'),
    'p2': TextEditingController(text: '${widget.t.pts.p2}'),
    'p3': TextEditingController(text: '${widget.t.pts.p3}'),
    'bye': TextEditingController(text: '${widget.t.pts.bye}'),
    'max': TextEditingController(text: '${widget.t.maxScores}'),
  };
  late FieldMode cmd = widget.t.commanderField;
  late FieldMode list = widget.t.deckListField;
  late ShareMode shareDecks = widget.t.shareDecks;
  late ShareMode shareVotes = widget.t.shareVotes;
  late ShareMode shareAch = widget.t.shareAchievements;
  late bool achOn = widget.t.achievementsOn;
  late List<Achievement> achs = widget.t.achievementList;
  late AchList? achList = widget.t.achListId == null
      ? null
      : AchList(widget.t.achListId!, widget.t.achListName ?? 'Lista');
  late List<String> tbs = List.of(widget.t.tiebreakers);

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
    final achMap = {for (final a in achs) a.id: a};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Configuración de la liga', style: TextStyle(fontWeight: FontWeight.w700)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event, color: kGold),
            title: Text('Inicio: ${fmtDate(t.eventDate)}'),
            subtitle: const Text('Toca para cambiarla (se guarda al instante)'),
            onTap: () async {
              final d = await pickDate(
                  context, DateTime.fromMillisecondsSinceEpoch(t.eventDate));
              if (d == null || !context.mounted) return;
              await guard(context,
                  () => Repo.i.setDate(t.code, d.millisecondsSinceEpoch));
            },
          ),
          Row(children: [_f('min', 'Minutos por ronda'), _f('max', 'Puntajes máximos (0 = todos)')]),
          Row(children: [_f('win', 'Victoria'), _f('draw', 'Empate'), _f('loss', 'Derrota')]),
          Row(children: [_f('p2', '2º lugar'), _f('p3', '3º lugar'), _f('bye', 'Bye')]),
          const Text(
              'Puntajes máximos: si eliges 3, el standing suma solo los 3 mejores puntajes de ronda de cada jugador.',
              style: TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Usar logros'),
            value: achOn,
            onChanged: (v) => setState(() => achOn = v),
          ),
          if (achOn) ...[
            AchievementSelector(
                owner: t.ownerId,
                listId: achList?.id,
                onListChanged: (l) => setState(() => achList = l),
                selected: achs,
                onChanged: (v) => setState(() {
                      achs = v;
                      final ids = v.map((a) => a.id).toSet();
                      tbs = tbs
                          .where((k) => !k.startsWith('ach:') || ids.contains(k.substring(4)))
                          .toList();
                    })),
            ShareModePicker(
                label: 'Quién ve el detalle de logros',
                value: shareAch,
                onChanged: (v) => setState(() => shareAch = v)),
          ],
          const SizedBox(height: 8),
          TiebreakEditor(
              value: tbs,
              achievements: achOn ? achMap : const {},
              onChanged: (v) => setState(() => tbs = v)),
          const SizedBox(height: 8),
          FieldModePicker(
              label: 'Baraja / Comandante', value: cmd, onChanged: (v) => setState(() => cmd = v)),
          FieldModePicker(
              label: 'Lista de la baraja (URL)', value: list, onChanged: (v) => setState(() => list = v)),
          ShareModePicker(
              label: 'Quién ve las barajas', value: shareDecks, onChanged: (v) => setState(() => shareDecks = v)),
          ShareModePicker(
              label: 'Quién ve los votos', value: shareVotes, onChanged: (v) => setState(() => shareVotes = v)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => guard(context, () async {
              await Repo.i.saveLeagueSettings(
                t,
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
                achievementsOn: achOn,
                achievements: achs,
                achList: achOn ? achList : null,
                tiebreakers: achOn
                    ? tbs
                    : tbs.where((k) => !k.startsWith('ach:')).toList(),
                maxScores: _n('max', 0).toInt().abs(),
                shareAchievements: shareAch,
              );
              final fresh = await Repo.i.peek(t.code);
              if (fresh != null) {
                await Repo.i.recomputeLeagueScores(fresh, widget.rounds, widget.claims);
              }
              if (context.mounted) toast(context, 'Ajustes guardados');
            }),
            child: const Text('Guardar cambios'),
          ),
        ]),
      ),
    );
  }
}
