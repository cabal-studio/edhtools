import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';

/// Mantenedor de preguntas de votación especial (ej. "Baraja más original").
class VoteQuestionsScreen extends StatefulWidget {
  /// null = mis preguntas; 'g_{id}' = preguntas de un grupo.
  final String? owner;
  final String title;
  const VoteQuestionsScreen(
      {super.key, this.owner, this.title = 'Preguntas de votación'});
  @override
  State<VoteQuestionsScreen> createState() => _VoteQuestionsScreenState();
}

class _VoteQuestionsScreenState extends State<VoteQuestionsScreen> {
  final _new = TextEditingController();
  late final Stream<List<String>> _stream = Repo.i.voteQuestions(owner: widget.owner);

  Future<void> _add() async {
    final q = _new.text.trim();
    if (q.isEmpty) return;
    _new.clear();
    await guard(context, () => Repo.i.saveVoteQuestions([q], owner: widget.owner));
  }

  Future<void> _edit(String q) async {
    final c = TextEditingController(text: q);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Editar pregunta'),
        content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(counterText: '')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(d, c.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (v == null || v.isEmpty || v == q || !mounted) return;
    await guard(context, () => Repo.i.renameVoteQuestion(q, v, owner: widget.owner));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: StreamBuilder<List<String>>(
        stream: _stream,
        builder: (context, snap) {
          final qs = snap.data ?? const <String>[];
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'Estas preguntas aparecen al activar la votación especial en una ronda. Los torneos ya jugados conservan sus preguntas aunque las edites o borres aquí.',
                style: TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _new,
                  maxLength: 60,
                  decoration: const InputDecoration(
                      hintText: 'Nueva pregunta, ej: Jugador más amable',
                      counterText: ''),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _add, child: const Text('Agregar')),
            ]),
            const SizedBox(height: 8),
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData)
              const Center(child: CircularProgressIndicator())
            else if (qs.isEmpty)
              const EmptyCard('Aún no tienes preguntas guardadas.'),
            for (final q in qs)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.how_to_vote, color: kGold),
                  title: Text(q),
                  onTap: () => _edit(q),
                  trailing: IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmDialog(context, '¿Borrar "$q"?',
                              ok: 'Borrar') &&
                          context.mounted) {
                        await guard(context, () => Repo.i.forgetVoteQuestion(q, owner: widget.owner));
                      }
                    },
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
