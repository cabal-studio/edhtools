import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import 'tournament_screen.dart';

/// Etiqueta del tipo de jugador: Google, App (anónimo) o Manual.
class KindBadge extends StatelessWidget {
  final RosterPerson p;
  const KindBadge(this.p, {super.key});
  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = p.isManual
        ? ('Manual', kMuted, Icons.edit_note)
        : p.google
            ? ('Google', kOk, Icons.verified_user)
            : ('App', kBlue, Icons.phone_android);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

enum _Filter { all, manual, app }

/// Mantenedor de jugadores: todos los que han participado en tus torneos.
class RosterScreen extends StatefulWidget {
  /// null = mis jugadores; 'g_{id}' = jugadores de un grupo.
  final String? owner;
  final String title;
  const RosterScreen({super.key, this.owner, this.title = 'Mis jugadores'});
  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _q = TextEditingController();
  _Filter filter = _Filter.all;
  late final Stream<List<RosterPerson>> _stream =
      Repo.i.rosterPeople(owner: widget.owner);

  Future<void> _delete(List<RosterPerson> ps) async {
    final ok = await confirmDialog(
        context,
        ps.length == 1
            ? '¿Eliminar a "${ps.first.nick}" del mantenedor? Los torneos donde jugó no cambian. No se puede deshacer.'
            : '¿Eliminar ${ps.length} jugadores ficticios (sin cuenta) del mantenedor? Los torneos donde jugaron no cambian. No se puede deshacer.',
        ok: 'Eliminar');
    if (!ok || !mounted) return;
    await guard(context, () async {
      await Repo.i.deleteRosterPeople(ps.map((p) => p.id), owner: widget.owner);
      if (mounted) toast(context, '${ps.length} jugador(es) eliminados');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: StreamBuilder<List<RosterPerson>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final q = _q.text.trim().toLowerCase();
          final all = snap.data!;
          final list = all.where((p) {
            if (filter == _Filter.manual && !p.isManual) return false;
            if (filter == _Filter.app && p.isManual) return false;
            return q.isEmpty || p.nick.toLowerCase().contains(q);
          }).toList();
          final manual = all.where((p) => p.isManual).length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'Todos los jugadores que han participado en tus torneos. Los manuales se reutilizan al agregarlos a un torneo nuevo.',
                style: TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 10),
            TextField(
              controller: _q,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            SegmentedButton<_Filter>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: _Filter.all, label: Text('Todos (${all.length})')),
                ButtonSegment(value: _Filter.manual, label: Text('Manuales ($manual)')),
                ButtonSegment(
                    value: _Filter.app, label: Text('Con cuenta (${all.length - manual})')),
              ],
              selected: {filter},
              onSelectionChanged: (s) => setState(() => filter = s.first),
            ),
            if (manual > 0 && filter != _Filter.app)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: kBad),
                  onPressed: () => _delete(all.where((p) => p.isManual).toList()),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text('Eliminar todos los ficticios ($manual)'),
                ),
              ),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const EmptyCard(
                  'No hay jugadores todavía. Aparecerán cuando se inscriban en tus torneos o los agregues manualmente.'),
            for (final p in list)
              Card(
                child: ListTile(
                  title: Text(p.nick),
                  subtitle: Text('${p.tournamentCount} torneo(s)'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    KindBadge(p),
                    if (p.isManual)
                      IconButton(
                        tooltip: 'Eliminar del mantenedor',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete([p]),
                      ),
                  ]),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              RosterPersonScreen(id: p.id, owner: widget.owner))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// Ficha de un jugador: nombre, torneos jugados y fusión con una cuenta.
class RosterPersonScreen extends StatelessWidget {
  final String id;
  final String? owner;
  const RosterPersonScreen({super.key, required this.id, this.owner});

  Future<void> _rename(BuildContext context, RosterPerson p) async {
    final c = TextEditingController(text: p.nick);
    final nick = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Editar nombre'),
        content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 24,
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
    if (nick == null || nick.isEmpty || !context.mounted) return;
    await guard(context, () => Repo.i.renameRosterPerson(p.id, nick, owner: owner));
  }

  Future<void> _merge(BuildContext context, RosterPerson manual) async {
    final target = await showDialog<RosterPerson>(
      context: context,
      builder: (d) => _AccountPicker(exclude: manual.id, owner: owner),
    );
    if (target == null || !context.mounted) return;
    final ok = await confirmDialog(
      context,
      '¿Fusionar "${manual.nick}" (manual, ${manual.tournamentCount} torneo(s)) con la cuenta de "${target.nick}"?\n\n'
      '• Sus torneos pasarán a esa cuenta y el jugador podrá verlos en su historial.\n'
      '• La ficha manual se eliminará.\n'
      '${target.google ? '' : '• Ojo: esa cuenta es anónima (sin Google); si el jugador borra la app, perderá el acceso.\n'}'
      '\nEsta acción no se puede deshacer.',
      ok: 'Fusionar',
    );
    if (!ok || !context.mounted) return;
    await guard(context, () async {
      await Repo.i.mergeRosterPeople(manual, target, owner: owner);
      if (!context.mounted) return;
      toast(context, 'Fusionado con ${target.nick}');
      Navigator.pushReplacement(context,
          MaterialPageRoute(
              builder: (_) => RosterPersonScreen(id: target.id, owner: owner)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RosterPerson?>(
      stream: Repo.i.rosterPerson(id, owner: owner),
      builder: (context, snap) {
        final p = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text(p?.nick ?? 'Jugador')),
          body: p == null
              ? Center(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const CircularProgressIndicator()
                      : const Text('Este jugador ya no existe'))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(p.nick,
                                    style: const TextStyle(
                                        fontSize: 20, fontWeight: FontWeight.w700)),
                              ),
                              KindBadge(p),
                            ]),
                            const SizedBox(height: 6),
                            Text(
                              p.isManual
                                  ? 'Jugador agregado manualmente. Si después juega con su cuenta de Google, puedes fusionarlo para que vea todo su historial.'
                                  : p.google
                                      ? 'Usa la app con su cuenta de Google.'
                                      : 'Usa la app como invitado (sin Google). Si vincula Google desde el menú de cuenta, quedará marcado en su próximo torneo.',
                              style: const TextStyle(color: kMuted, fontSize: 12.5),
                            ),
                            if (p.mergedFrom.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                    'Incluye ${p.mergedFrom.length} ficha(s) manual(es) fusionada(s).',
                                    style: const TextStyle(color: kMuted, fontSize: 12.5)),
                              ),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              if (p.isManual)
                                OutlinedButton.icon(
                                    onPressed: () => _rename(context, p),
                                    icon: const Icon(Icons.edit, size: 18),
                                    label: const Text('Editar nombre')),
                              if (p.isManual)
                                FilledButton.icon(
                                    onPressed: () => _merge(context, p),
                                    icon: const Icon(Icons.merge, size: 18),
                                    label: const Text('Fusionar con cuenta')),
                            ]),
                          ]),
                    ),
                  ),
                  SectionTitle('Torneos (${p.tournamentCount})'),
                  if (p.tournaments.isEmpty) const EmptyCard('Sin torneos.'),
                  for (final x in p.tournaments)
                    Card(
                      child: ListTile(
                        title: Text(x.name),
                        subtitle: Text(_date(x.at)),
                        trailing: Text(x.code,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                color: kGoldLight,
                                letterSpacing: 2)),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => TournamentScreen(
                                    code: x.code, startOnStanding: true))),
                      ),
                    ),
                ]),
        );
      },
    );
  }

  static String _date(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
  }
}

/// Elige la cuenta (Google primero) con la que fusionar una ficha manual.
class _AccountPicker extends StatefulWidget {
  final String exclude;
  final String? owner;
  const _AccountPicker({required this.exclude, this.owner});
  @override
  State<_AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends State<_AccountPicker> {
  final _q = TextEditingController();
  late final Stream<List<RosterPerson>> _stream =
      Repo.i.rosterPeople(owner: widget.owner);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fusionar con…'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: StreamBuilder<List<RosterPerson>>(
          stream: _stream,
          builder: (context, snap) {
            final q = _q.text.trim().toLowerCase();
            final list = (snap.data ?? const <RosterPerson>[])
                .where((p) =>
                    !p.isManual &&
                    p.id != widget.exclude &&
                    (q.isEmpty || p.nick.toLowerCase().contains(q)))
                .toList()
              ..sort((a, b) => (b.google ? 1 : 0) - (a.google ? 1 : 0));
            return Column(children: [
              TextField(
                controller: _q,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Buscar cuenta'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              const Text(
                  'Solo aparecen jugadores que han usado la app en alguno de tus torneos.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text('No hay cuentas disponibles',
                            style: TextStyle(color: kMuted)))
                    : ListView(children: [
                        for (final p in list)
                          ListTile(
                            title: Text(p.nick),
                            subtitle: Text('${p.tournamentCount} torneo(s)'),
                            trailing: KindBadge(p),
                            onTap: () => Navigator.pop(context, p),
                          ),
                      ]),
              ),
            ]);
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}
