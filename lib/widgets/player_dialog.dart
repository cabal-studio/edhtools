import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../ui/theme.dart';
import 'common.dart';

class PlayerForm {
  final String nick;
  final DeckInfo deck;
  const PlayerForm(this.nick, this.deck);
}

/// Pide nick y datos de baraja según la configuración del torneo.
Future<PlayerForm?> playerDialog(
  BuildContext context,
  Tournament t, {
  required String title,
  String okLabel = 'Guardar',
  String nick = '',
  DeckInfo deck = const DeckInfo(),
  bool askNick = true,
}) {
  return showDialog<PlayerForm>(
    context: context,
    builder: (c) => _PlayerDialog(
      t: t,
      title: title,
      okLabel: okLabel,
      nick: nick,
      deck: deck,
      askNick: askNick,
    ),
  );
}

class _PlayerDialog extends StatefulWidget {
  final Tournament t;
  final String title, okLabel, nick;
  final DeckInfo deck;
  final bool askNick;
  const _PlayerDialog({
    required this.t,
    required this.title,
    required this.okLabel,
    required this.nick,
    required this.deck,
    required this.askNick,
  });
  @override
  State<_PlayerDialog> createState() => _PlayerDialogState();
}

class _PlayerDialogState extends State<_PlayerDialog> {
  late final _nick = TextEditingController(text: widget.nick);
  late final _cmd = TextEditingController(text: widget.deck.commander);
  late final _url = TextEditingController(text: widget.deck.listUrl);
  String? error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.askNick)
              TextField(
                controller: _nick,
                autofocus: true,
                maxLength: 24,
                decoration: const InputDecoration(
                    labelText: 'Nombre / nick', counterText: ''),
              ),
            DeckFields(t: widget.t, commander: _cmd, listUrl: _url),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: kBad)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final n = _nick.text.trim();
            if (widget.askNick && n.isEmpty) {
              setState(() => error = 'Ingresa un nombre');
              return;
            }
            final e = DeckFields.validate(widget.t, _cmd.text, _url.text);
            if (e != null) {
              setState(() => error = e);
              return;
            }
            Navigator.pop(
                context,
                PlayerForm(
                    n,
                    DeckInfo(
                        commander: _cmd.text.trim(),
                        listUrl: _url.text.trim())));
          },
          child: Text(widget.okLabel),
        ),
      ],
    );
  }
}
