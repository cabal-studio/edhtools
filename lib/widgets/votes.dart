import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/swiss.dart';
import '../ui/theme.dart';
import 'common.dart';

/// Diálogo del organizador: elige las preguntas de votación de una ronda.
/// Las preguntas usadas se guardan para futuros torneos.
Future<List<String>?> editVoteQuestions(
    BuildContext context, List<String> current) {
  return showDialog<List<String>>(
    context: context,
    builder: (c) => _VoteQuestionsDialog(current: current),
  );
}

class _VoteQuestionsDialog extends StatefulWidget {
  final List<String> current;
  const _VoteQuestionsDialog({required this.current});
  @override
  State<_VoteQuestionsDialog> createState() => _VoteQuestionsDialogState();
}

class _VoteQuestionsDialogState extends State<_VoteQuestionsDialog> {
  late final List<String> qs = List.of(widget.current);
  final _text = TextEditingController();

  void _add(String q) {
    final v = q.trim();
    if (v.isEmpty || qs.contains(v)) return;
    setState(() => qs.add(v));
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Votación especial'),
      content: SizedBox(
        width: 420,
        child: StreamBuilder<Map<String, dynamic>>(
          stream: Repo.i.me(),
          builder: (context, snap) {
            final saved = List<String>.from(
                    (snap.data ?? const {})['voteQuestions'] ?? const [])
                .where((q) => !qs.contains(q))
                .toList();
            return ListView(shrinkWrap: true, children: [
              const Text(
                  'Durante la ronda, cada jugador podrá votar por un oponente de su mesa (o dejarlo vacío).',
                  style: TextStyle(color: kMuted, fontSize: 12.5)),
              const SizedBox(height: 10),
              for (final q in qs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.how_to_vote, color: kGold),
                  title: Text(q),
                  trailing: IconButton(
                      tooltip: 'Quitar de esta ronda',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => qs.remove(q))),
                ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    maxLength: 60,
                    decoration: const InputDecoration(
                        hintText: 'Ej: Baraja más original', counterText: ''),
                    onSubmitted: _add,
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _add(_text.text)),
              ]),
              if (saved.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Preguntas guardadas',
                    style: TextStyle(color: kMuted, fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final q in saved)
                    InputChip(
                      label: Text(q),
                      onPressed: () => _add(q),
                      onDeleted: () => Repo.i.forgetVoteQuestion(q),
                      deleteButtonTooltipMessage: 'Olvidar pregunta',
                    ),
                ]),
              ],
            ]);
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              if (_text.text.trim().isNotEmpty) _add(_text.text);
              Navigator.pop(context, qs);
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

/// Tarjeta del jugador para votar durante la ronda.
class PlayerVoteCard extends StatefulWidget {
  final String code;
  final RoundData round;
  final List<String> opponents;
  final String Function(String) nick;
  const PlayerVoteCard({
    super.key,
    required this.code,
    required this.round,
    required this.opponents,
    required this.nick,
  });
  @override
  State<PlayerVoteCard> createState() => _PlayerVoteCardState();
}

class _PlayerVoteCardState extends State<PlayerVoteCard> {
  Map<String, String?>? draft;
  bool sending = false;

  @override
  Widget build(BuildContext context) {
    final qs = widget.round.voteQuestions;
    return StreamBuilder<Vote?>(
      stream: Repo.i.myVote(widget.code, widget.round.n),
      builder: (context, snap) {
        final sent = snap.data;
        final d = draft ?? Map<String, String?>.from(sent?.picks ?? const {});
        return Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: kGold.withValues(alpha: .5))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [
                Icon(Icons.how_to_vote, color: kGold),
                SizedBox(width: 8),
                Text('Votación especial',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ]),
              const SizedBox(height: 4),
              const Text('Elige un oponente de tu mesa o déjalo vacío. Tu voto es privado.',
                  style: TextStyle(color: kMuted, fontSize: 12.5)),
              for (var i = 0; i < qs.length; i++) ...[
                const SizedBox(height: 12),
                Text(qs[i], style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                DropdownButton<String?>(
                  value: widget.opponents.contains(d['$i']) ? d['$i'] : null,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— Sin voto —')),
                    for (final o in widget.opponents)
                      DropdownMenuItem<String?>(
                          value: o, child: Text(widget.nick(o))),
                  ],
                  onChanged: (v) => setState(() {
                    draft = Map.of(d)..['$i'] = v;
                  }),
                ),
              ],
              const SizedBox(height: 12),
              if (sent != null && draft == null)
                const Text('Voto enviado ✓ (puedes cambiarlo durante la ronda)',
                    style: TextStyle(color: kOk, fontSize: 13)),
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        setState(() => sending = true);
                        await guard(context, () async {
                          final picks = <String, String?>{
                            for (var i = 0; i < qs.length; i++) '$i': d['$i'],
                          };
                          await Repo.i.sendVote(widget.code, widget.round.n, picks);
                          if (mounted) setState(() => draft = null);
                          if (context.mounted) toast(context, 'Voto enviado');
                        });
                        if (mounted) setState(() => sending = false);
                      },
                child: Text(sent == null ? 'Enviar voto' : 'Actualizar voto'),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Resultados de las votaciones (organizador, o todos si se comparten).
class VoteResults extends StatelessWidget {
  final List<Vote> votes;
  final List<RoundData> rounds;
  final String Function(String) nick;
  const VoteResults(
      {super.key, required this.votes, required this.rounds, required this.nick});

  @override
  Widget build(BuildContext context) {
    final withQ = rounds.where((r) => r.voteQuestions.isNotEmpty).toList();
    if (withQ.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Votaciones especiales'),
      for (final r in withQ)
        for (var i = 0; i < r.voteQuestions.length; i++)
          _questionCard(r, i),
    ]);
  }

  Widget _questionCard(RoundData r, int i) {
    final counts = <String, int>{};
    var total = 0;
    for (final v in votes.where((v) => v.round == r.n)) {
      final pick = v.picks['$i'];
      if (pick != null) {
        counts[pick] = (counts[pick] ?? 0) + 1;
        total++;
      }
    }
    final ranking = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('R${r.n} · ${r.voteQuestions[i]}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('$total voto(s)', style: const TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 6),
          if (ranking.isEmpty)
            const Text('Sin votos aún', style: TextStyle(color: kMuted)),
          for (final e in ranking)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(nick(e.key))),
                Text('${e.value}',
                    style: const TextStyle(
                        color: kGoldLight, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    );
  }
}
