import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/swiss.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import 'tournament_screen.dart';

/// Historial de torneos en los que el usuario jugó u organizó.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// Torneos en que jugué como jugador manual y luego me vincularon a mi cuenta.
  late final Future<List<MyTournamentRef>> _linked =
      Repo.i.linkedTournaments().catchError((_) => <MyTournamentRef>[]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi historial')),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: Repo.i.me(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final me = snap.data!;
          return FutureBuilder<List<MyTournamentRef>>(
            future: _linked,
            builder: (context, linked) {
          final seen = <String>{};
          final items = <MyTournamentRef>[
            for (final r in [
              ...Repo.refs(me, 'joined'),
              ...(linked.data ?? const <MyTournamentRef>[]),
              ...Repo.refs(me, 'organized'),
            ])
              if (seen.add(r.code)) r,
          ];
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyCard('Aún no has participado en torneos.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                  'Toca un torneo para ver su standing y el detalle de cada ronda.',
                  style: TextStyle(color: kMuted, fontSize: 12.5)),
              const SizedBox(height: 8),
              for (final r in items) _HistoryTile(ref: r),
            ],
          );
            },
          );
        },
      ),
    );
  }
}

class _Summary {
  final Tournament t;
  final Standing? me;
  final int total;
  _Summary(this.t, this.me, this.total);
}

class _HistoryTile extends StatefulWidget {
  final MyTournamentRef ref;
  const _HistoryTile({required this.ref});
  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  late final Future<_Summary?> _f = _load();

  Future<_Summary?> _load() async {
    final repo = Repo.i;
    final t = await repo.peek(widget.ref.code);
    if (t == null) return null;
    final ps = await repo.playersOnce(t.code);
    final rs = (await repo.roundsOnce(t.code)).where((r) => r.confirmed).toList();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final st = computeStandings(rs, ps, t.pts);
    // Mi registro: el indicado por la vinculación, mi uid, o una ficha fusionada.
    final myId = widget.ref.pid ??
        (ps.containsKey(uid)
            ? uid
            : ps.values.where((p) => p.uid == uid).map((p) => p.id).firstOrNullX);
    final mine = st.where((s) => s.id == myId);
    return _Summary(t, mine.isEmpty ? null : mine.first, ps.length);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Summary?>(
      future: _f,
      builder: (context, snap) {
        final s = snap.data;
        // Torneos borrados no se muestran.
        if (snap.connectionState == ConnectionState.done && s == null) {
          return const SizedBox.shrink();
        }
        final uid = FirebaseAuth.instance.currentUser!.uid;
        String sub;
        if (snap.connectionState != ConnectionState.done) {
          sub = 'Cargando…';
        } else if (s == null) {
          sub = '';
        } else {
          final status = switch (s.t.status) {
            'registration' => 'Inscripción',
            'prep' || 'round' => 'En curso · ronda ${s.t.currentRound}',
            _ => 'Finalizado',
          };
          final role = s.t.organizerId == uid ? 'Organizador · ' : '';
          final pos = s.me == null
              ? ''
              : ' · #${s.me!.rank} de ${s.total} · ${s.me!.pts} pts';
          sub = '$role$status$pos';
        }
        return Card(
          child: ListTile(
            leading: Icon(
                s != null && s.me != null && s.me!.rank <= 3 && s.t.status == 'finished'
                    ? Icons.emoji_events
                    : Icons.history,
                color: kGold),
            title: Text(widget.ref.name),
            subtitle: Text(sub),
            trailing: Text(widget.ref.code,
                style: const TextStyle(
                    fontFamily: 'monospace', color: kGoldLight, letterSpacing: 2)),
            onTap: s == null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TournamentScreen(
                            code: widget.ref.code, startOnStanding: true))),
          ),
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNullX => isEmpty ? null : first;
}
