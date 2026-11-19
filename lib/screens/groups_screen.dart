import 'package:flutter/material.dart';

import '../data/auth.dart';
import '../data/repo.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';
import '../widgets/tournament_tile.dart';
import 'achievements_screen.dart';
import 'organize_screen.dart';
import 'roster_screen.dart';
import 'vote_questions_screen.dart';

Future<String?> _askName(BuildContext context, String title,
    {String initial = '', String ok = 'Guardar'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 40,
        decoration:
            const InputDecoration(labelText: 'Nombre del grupo', counterText: ''),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

/// Grupos de organizadores a los que pertenezco (como dueño o miembro).
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});
  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final Stream<List<Group>> _stream = Repo.i.myGroups();
  bool _busy = false;

  Future<void> _create() async {
    final name = await _askName(context, 'Nuevo grupo', ok: 'Crear');
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _busy = true);
    await guard(context, () async {
      final id = await Repo.i.createGroup(name, Auth.displayName);
      if (!mounted) return;
      toast(context, 'Grupo creado con una copia de tus mantenedores');
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => GroupScreen(id: id)));
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final me = Repo.i.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Grupos de organizadores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.add),
        label: Text(_busy ? 'Creando…' : 'Crear grupo'),
      ),
      body: StreamBuilder<List<Group>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            const Text(
                'Un grupo funciona como un organizador aparte: tiene sus propios jugadores, preguntas y logros, y su propio historial. '
                'Al crearlo se copian tus mantenedores. Sus miembros pueden organizar torneos como parte del grupo.',
                style: TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 10),
            if (list.isEmpty)
              const EmptyCard('Aún no perteneces a ningún grupo.'),
            for (final g in list)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.diversity_3, color: kGold),
                  title: Text(g.name),
                  subtitle: Text(
                      '${g.members.length} miembro(s) · ${g.tournaments.length} torneo(s)'),
                  trailing: g.ownerUid == me
                      ? const Text('Dueño', style: TextStyle(color: kGoldLight))
                      : const Text('Miembro', style: TextStyle(color: kMuted)),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => GroupScreen(id: g.id))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// Detalle de un grupo: organizar, mantenedores, miembros e historial.
class GroupScreen extends StatefulWidget {
  final String id;
  const GroupScreen({super.key, required this.id});
  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late final Stream<Group?> _stream = Repo.i.group(widget.id);

  void _go(Widget w) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  Future<void> _addMember(Group g) async {
    final p = await showDialog<RosterPerson>(
      context: context,
      builder: (_) => _MemberPicker(exclude: g.members.toSet()),
    );
    if (p == null || !mounted) return;
    await guard(context, () => Repo.i.addGroupMember(g.id, p));
  }

  Future<void> _remove(Group g, String u) async {
    final ok = await confirmDialog(context,
        '¿Quitar a ${g.nameOf(u)} del grupo? Dejará de ver y usar sus mantenedores. Los torneos que ya organizó siguen en el historial.',
        ok: 'Quitar');
    if (!ok || !mounted) return;
    await guard(context, () => Repo.i.removeGroupMember(g.id, u));
  }

  Future<void> _leave(Group g) async {
    final ok = await confirmDialog(context,
        '¿Salir del grupo "${g.name}"? Solo el dueño podrá volver a agregarte.',
        ok: 'Salir');
    if (!ok || !mounted) return;
    await guard(context, () async {
      await Repo.i.leaveGroup(g.id);
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _rename(Group g) async {
    final name = await _askName(context, 'Renombrar grupo', initial: g.name);
    if (name == null || name.isEmpty || !mounted) return;
    await guard(context, () => Repo.i.renameGroup(g.id, name));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Group?>(
      stream: _stream,
      builder: (context, snap) {
        final g = snap.data;
        if (g == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Grupo')),
            body: Center(
              child: snap.hasError
                  ? const Text('No perteneces a este grupo.')
                  : snap.connectionState == ConnectionState.waiting
                      ? const CircularProgressIndicator()
                      : const Text('Este grupo ya no existe.'),
            ),
          );
        }
        final me = Repo.i.uid;
        final isOwner = g.ownerUid == me;
        final members = [...g.members]
          ..sort((a, b) {
            if (a == g.ownerUid) return -1;
            if (b == g.ownerUid) return 1;
            return g.nameOf(a).toLowerCase().compareTo(g.nameOf(b).toLowerCase());
          });
        return Scaffold(
          appBar: AppBar(
            title: Text(g.name),
            actions: [
              if (isOwner)
                IconButton(
                    tooltip: 'Renombrar',
                    onPressed: () => _rename(g),
                    icon: const Icon(Icons.edit)),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              onPressed: () => _go(OrganizeScreen(group: g)),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Organizar torneo como grupo'),
            ),
            const SectionTitle('Mantenedores del grupo'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => _go(RosterScreen(
                    owner: g.owner, title: 'Jugadores · ${g.name}')),
                icon: const Icon(Icons.groups),
                label: const Text('Jugadores'),
              ),
              OutlinedButton.icon(
                onPressed: () => _go(VoteQuestionsScreen(
                    owner: g.owner, title: 'Preguntas · ${g.name}')),
                icon: const Icon(Icons.how_to_vote),
                label: const Text('Preguntas'),
              ),
              OutlinedButton.icon(
                onPressed: () => _go(AchievementsScreen(
                    owner: g.owner, title: 'Logros · ${g.name}')),
                icon: const Icon(Icons.military_tech),
                label: const Text('Logros'),
              ),
            ]),
            SectionTitle('Miembros (${g.members.length})',
                trailing: isOwner
                    ? TextButton.icon(
                        onPressed: () => _addMember(g),
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('Agregar'))
                    : null),
            Card(
              child: Column(children: [
                for (final u in members)
                  ListTile(
                    leading: Icon(
                        u == g.ownerUid ? Icons.workspace_premium : Icons.person,
                        color: u == g.ownerUid ? kGold : kMuted),
                    title: Text(g.nameOf(u) + (u == me ? ' (tú)' : '')),
                    subtitle: Text(u == g.ownerUid ? 'Dueño' : 'Miembro'),
                    trailing: isOwner && u != g.ownerUid
                        ? IconButton(
                            tooltip: 'Quitar del grupo',
                            onPressed: () => _remove(g, u),
                            icon: const Icon(Icons.person_remove_outlined))
                        : null,
                  ),
              ]),
            ),
            if (isOwner)
              const Text(
                  'Puedes agregar jugadores de tu mantenedor que usen la app con su cuenta (Google o invitado). Los jugadores manuales no pueden ser miembros.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
            if (!isOwner)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _leave(g),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Salir del grupo'),
                ),
              ),
            SectionTitle('Historial del grupo (${g.tournaments.length})'),
            if (g.tournaments.isEmpty)
              const EmptyCard('Todavía no hay torneos organizados como grupo.'),
            for (final t in g.tournaments)
              TournamentTile(key: ValueKey(t.code), ref: t),
          ]),
        );
      },
    );
  }
}

/// Elige un jugador con cuenta de mi mantenedor para sumarlo al grupo.
class _MemberPicker extends StatefulWidget {
  final Set<String> exclude;
  const _MemberPicker({required this.exclude});
  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  final _q = TextEditingController();
  late final Stream<List<RosterPerson>> _stream = Repo.i.rosterPeople();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar miembro'),
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
                    p.uid != null &&
                    !widget.exclude.contains(p.uid) &&
                    (q.isEmpty || p.nick.toLowerCase().contains(q)))
                .toList()
              ..sort((a, b) => (b.google ? 1 : 0) - (a.google ? 1 : 0));
            return Column(children: [
              TextField(
                controller: _q,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Buscar jugador'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              const Text('Solo jugadores de tu mantenedor que usan la app.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 8),
              Expanded(
                child: !snap.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                        ? const Center(
                            child: Text('No hay jugadores disponibles',
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
