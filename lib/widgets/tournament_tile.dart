import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../screens/tournament_screen.dart';
import '../ui/theme.dart';

/// Etiqueta corta del estado de un torneo o liga.
String statusLabel(Tournament t) => switch (t.status) {
      'registration' => t.isLeague
          ? 'Liga · inscripción ronda ${t.currentRound}'
          : 'Inscripción abierta',
      'between' => t.currentRound == 0
          ? 'Liga · sin rondas aún'
          : 'Liga · ${t.currentRound} ronda(s) jugadas',
      'prep' => '${t.isLeague ? 'Liga · ' : ''}Preparando ronda ${t.currentRound}',
      'round' => '${t.isLeague ? 'Liga · ' : ''}En juego · ronda ${t.currentRound}',
      _ => t.isLeague ? 'Liga finalizada' : 'Finalizado',
    };

/// Torneo en una lista: nombre, fecha, estado y clave. Borde verde si está
/// abierto o en curso.
class TournamentTile extends StatefulWidget {
  final MyTournamentRef ref;
  const TournamentTile({super.key, required this.ref});
  @override
  State<TournamentTile> createState() => _TournamentTileState();
}

class _TournamentTileState extends State<TournamentTile> {
  late final Stream<Tournament?> _stream = Repo.i.tournament(widget.ref.code);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tournament?>(
      stream: _stream,
      builder: (context, snap) {
        final t = snap.data;
        if (snap.connectionState == ConnectionState.active && t == null) {
          return const SizedBox.shrink(); // borrado
        }
        final active = t?.isActive ?? false;
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: active ? kOk : kLine, width: active ? 2 : 1),
          ),
          child: ListTile(
            leading: Icon(
                t?.isLeague ?? false ? Icons.calendar_month : Icons.emoji_events_outlined,
                color: active ? kOk : kMuted),
            title: Text(t?.name ?? widget.ref.name),
            subtitle: Text(t == null
                ? 'Cargando…'
                : [fmtDate(t.eventDate), statusLabel(t)]
                    .where((x) => x.isNotEmpty)
                    .join(' · ')),
            trailing: Text(widget.ref.code,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    color: kGoldLight,
                    letterSpacing: 2)),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TournamentScreen(code: widget.ref.code))),
          ),
        );
      },
    );
  }
}
