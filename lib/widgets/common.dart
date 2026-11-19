import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../logic/swiss.dart';
import '../ui/theme.dart';

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: const TextStyle(
                    color: kMuted, fontSize: 12.5, letterSpacing: 1)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyCard extends StatelessWidget {
  final String text;
  final Widget? action;
  const EmptyCard(this.text, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted)),
            if (action != null) ...[const SizedBox(height: 10), action!],
          ]),
        ),
      );
}

class Stat extends StatelessWidget {
  final String label, value;
  const Stat(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
        Text(value,
            style: const TextStyle(
                color: kGoldLight, fontSize: 24, fontWeight: FontWeight.w700)),
      ]);
}

Color resultColor(String v) => switch (v) {
      'W' => kOk,
      'D' => kBlue,
      'L' => const Color(0xFF5C5472),
      _ => kGold,
    };

class ResultChips extends StatelessWidget {
  final Points pts;
  final String? current;
  final void Function(String v)? onPick;
  const ResultChips(
      {super.key, required this.pts, this.current, this.onPick});

  @override
  Widget build(BuildContext context) {
    final opts =
        pts.usesPlacement ? ['W', '2', '3', 'L', 'D'] : ['W', 'D', 'L'];
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final v in opts)
        ChoiceChip(
          label: Text(kResultLabels[v]!),
          selected: current == v,
          selectedColor: resultColor(v),
          visualDensity: VisualDensity.compact,
          showCheckmark: false,
          onSelected: onPick == null ? null : (_) => onPick!(v),
        ),
    ]);
  }
}

class ResultBadge extends StatelessWidget {
  final Points pts;
  final String? value;
  const ResultBadge({super.key, required this.pts, this.value});
  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null) return const Text('—', style: TextStyle(color: kMuted));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: resultColor(v).withValues(alpha: .25),
          borderRadius: BorderRadius.circular(8)),
      child: Text('${kResultLabels[v]} · ${pts.forResult(v)}p',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Reloj de la ronda, visible para organizador y jugadores.
class TimerBox extends StatefulWidget {
  final Tournament t;
  const TimerBox({super.key, required this.t});
  @override
  State<TimerBox> createState() => _TimerBoxState();
}

class _TimerBoxState extends State<TimerBox> {
  late final Timer _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = widget.t.remainingMs();
    final paused = widget.t.timerPaused != null;
    String txt;
    String label;
    var color = Colors.white;
    var border = kLine;
    if (ms == null) {
      txt = '--:--';
      label = 'Ingreso de puntajes';
      color = kMuted;
    } else {
      final neg = ms < 0;
      final a = ms.abs();
      txt =
          '${neg ? '+' : ''}${a ~/ 60000}:${((a % 60000) ~/ 1000).toString().padLeft(2, '0')}';
      label = neg
          ? '¡Tiempo! Turnos extra'
          : paused
              ? 'En pausa'
              : 'Tiempo restante';
      if (neg) {
        color = kBad;
        border = kBad;
      } else if (paused) {
        color = kMuted;
      }
    }
    return Container(
      width: 124,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF150F27),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(children: [
        Text(txt,
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: color)),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 11)),
      ]),
    );
  }
}

/// Campos de baraja (comandante + lista) según la configuración del torneo.
class DeckFields extends StatelessWidget {
  final Tournament t;
  final TextEditingController commander;
  final TextEditingController listUrl;
  const DeckFields(
      {super.key,
      required this.t,
      required this.commander,
      required this.listUrl});

  String _label(String base, FieldMode m) =>
      m == FieldMode.required ? '$base *' : '$base (opcional)';

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (t.commanderField != FieldMode.off) ...[
        const SizedBox(height: 10),
        TextField(
          controller: commander,
          maxLength: 80,
          decoration: InputDecoration(
              labelText: _label('Baraja / Comandante', t.commanderField),
              counterText: ''),
        ),
      ],
      if (t.deckListField != FieldMode.off) ...[
        const SizedBox(height: 10),
        TextField(
          controller: listUrl,
          keyboardType: TextInputType.url,
          maxLength: 300,
          decoration: InputDecoration(
              labelText: _label('Lista de la baraja (URL)', t.deckListField),
              hintText: 'https://moxfield.com/decks/…',
              counterText: ''),
        ),
      ],
      if (t.asksDeck)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            switch (t.shareDecks) {
              ShareMode.never => 'Solo el organizador verá estos datos.',
              ShareMode.always => 'Todos los jugadores verán estos datos.',
              ShareMode.end =>
                'El organizador los ve; el resto, al finalizar el torneo.',
            },
            style: const TextStyle(color: kMuted, fontSize: 12),
          ),
        ),
    ]);
  }

  /// Devuelve un mensaje de error si falta un campo obligatorio.
  static String? validate(Tournament t, String commander, String listUrl) {
    if (t.commanderField == FieldMode.required && commander.trim().isEmpty) {
      return 'Este torneo pide el nombre de tu baraja / comandante';
    }
    if (t.deckListField == FieldMode.required && listUrl.trim().isEmpty) {
      return 'Este torneo pide el link de tu lista';
    }
    final u = listUrl.trim();
    if (u.isNotEmpty && !RegExp(r'^https?://').hasMatch(u)) {
      return 'El link de la lista debe empezar con https://';
    }
    return null;
  }
}
