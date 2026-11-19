import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../logic/league.dart';
import '../ui/theme.dart';
import '../widgets/common.dart';

/// Mantenedor de logros para las ligas: manual o carga desde CSV.
class AchievementsScreen extends StatefulWidget {
  /// null = mi catálogo; 'g_{id}' = catálogo de un grupo.
  final String? owner;
  final String title;
  const AchievementsScreen({super.key, this.owner, this.title = 'Logros'});
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late final Stream<List<Achievement>> _stream = Repo.i.achievementCatalog(owner: widget.owner);
  List<Achievement> _current = const [];

  Future<void> _edit([Achievement? a]) async {
    final res = await editAchievementDialog(context, a,
        taken: _current.map((x) => x.id).toSet());
    if (res == null || !mounted) return;
    await guard(context, () => Repo.i.saveAchievement(res, owner: widget.owner));
  }

  Future<void> _importCsv() async {
    final text = await showDialog<String>(
        context: context, builder: (c) => const _CsvDialog());
    if (text == null || text.trim().isEmpty || !mounted) return;
    final r = parseAchievementsCsv(text,
        takenIds: _current.map((x) => x.id).toSet());
    if (r.items.isEmpty) {
      toast(context,
          r.errors.isEmpty ? 'El archivo no tiene logros' : r.errors.first);
      return;
    }
    final ok = await confirmDialog(
      context,
      'Se agregarán ${r.items.length} logro(s).'
      '${r.errors.isEmpty ? '' : '\n\n${r.errors.length} fila(s) con problemas se omitirán:\n${r.errors.take(5).join('\n')}'}',
      ok: 'Importar',
    );
    if (!ok || !mounted) return;
    await guard(context, () => Repo.i.importAchievements(r.items, owner: widget.owner));
    if (mounted) toast(context, '${r.items.length} logro(s) importados');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Copiar como CSV',
            icon: const Icon(Icons.copy_all),
            onPressed: _current.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                        ClipboardData(text: achievementsToCsv(_current)));
                    if (context.mounted) toast(context, 'CSV copiado');
                  },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo logro'),
      ),
      body: StreamBuilder<List<Achievement>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          _current = snap.data!;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            const Text(
                'Logros disponibles para tus ligas. Al crear o configurar una liga eliges cuáles usar.',
                style: TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _importCsv,
              icon: const Icon(Icons.upload_file),
              label: const Text('Importar desde CSV'),
            ),
            const SizedBox(height: 8),
            if (_current.isEmpty) const EmptyCard('Aún no tienes logros.'),
            for (final a in _current)
              Card(
                child: ListTile(
                  title: Text(a.name),
                  subtitle: Text([
                    kAchTypeLabels[a.type]!,
                    '${a.points} pts',
                    if (a.description.isNotEmpty) a.description,
                  ].join(' · ')),
                  onTap: () => _edit(a),
                  trailing: IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmDialog(context,
                              '¿Borrar "${a.name}" del catálogo? Las ligas que ya lo usan lo conservan.',
                              ok: 'Borrar') &&
                          context.mounted) {
                        await guard(
                            context, () => Repo.i.deleteAchievement(a.id, owner: widget.owner));
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

/// Crea o edita un logro.
Future<Achievement?> editAchievementDialog(BuildContext context, Achievement? a,
    {Set<String> taken = const {}}) {
  return showDialog<Achievement>(
    context: context,
    builder: (c) => _AchDialog(a: a, taken: taken),
  );
}

class _AchDialog extends StatefulWidget {
  final Achievement? a;
  final Set<String> taken;
  const _AchDialog({this.a, required this.taken});
  @override
  State<_AchDialog> createState() => _AchDialogState();
}

class _AchDialogState extends State<_AchDialog> {
  late final _name = TextEditingController(text: widget.a?.name ?? '');
  late final _desc = TextEditingController(text: widget.a?.description ?? '');
  late final _pts = TextEditingController(text: '${widget.a?.points ?? 1}');
  late AchType type = widget.a?.type ?? AchType.player;
  String? error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.a == null ? 'Nuevo logro' : 'Editar logro'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                controller: _name,
                autofocus: true,
                maxLength: 50,
                decoration:
                    const InputDecoration(labelText: 'Nombre', counterText: '')),
            const SizedBox(height: 8),
            TextField(
                controller: _desc,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Descripción', counterText: '')),
            const SizedBox(height: 8),
            DropdownButtonFormField<AchType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                for (final t in AchType.values)
                  DropdownMenuItem(value: t, child: Text(kAchTypeLabels[t]!)),
              ],
              onChanged: (v) => setState(() => type = v ?? type),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                switch (type) {
                  AchType.auto => 'Todos los jugadores lo reciben al comenzar la ronda.',
                  AchType.player => 'Cada jugador puede reclamarlo una vez por ronda.',
                  AchType.round => 'Solo un jugador puede reclamarlo por ronda (el primero).',
                  AchType.unlimited => 'Se puede reclamar cuantas veces se quiera.',
                },
                style: const TextStyle(color: kMuted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
                controller: _pts,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                    labelText: 'Puntos', hintText: 'Ej: 1, 2 o -1')),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'Pueden ser negativos: un logro con -1 resta un punto al jugador que lo obtiene.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
            ),
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
            final name = _name.text.trim();
            final pts = num.tryParse(_pts.text.trim().replaceAll(',', '.'));
            if (name.isEmpty) return setState(() => error = 'Falta el nombre');
            if (pts == null) {
              return setState(() => error = 'Los puntos deben ser un número (puede ser negativo)');
            }
            final id = widget.a?.id ?? achIdFromName(name, widget.taken);
            Navigator.pop(
                context,
                Achievement(
                    id: id,
                    name: name,
                    description: _desc.text.trim(),
                    type: type,
                    points: pts));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Pegar CSV o elegir un archivo .csv.
class _CsvDialog extends StatefulWidget {
  const _CsvDialog();
  @override
  State<_CsvDialog> createState() => _CsvDialogState();
}

class _CsvDialogState extends State<_CsvDialog> {
  final _text = TextEditingController();

  Future<void> _pick() async {
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt'],
        withData: true,
      );
      final bytes = r?.files.single.bytes;
      if (bytes == null) return;
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = latin1.decode(bytes); // CSV de Excel en Windows
      }
      setState(() => _text.text = text);
    } catch (e) {
      if (mounted) toast(context, 'No se pudo leer el archivo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importar logros'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
                'Columnas: Nombre, Descripcion, Tipo, Puntos (pueden ser negativos).\n'
                'Tipo: Automático, Una vez por jugador, Una vez por ronda o Sin límite.\n'
                'Separador coma o punto y coma; la fila de encabezado es opcional.',
                style: TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Elegir archivo .csv')),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              decoration: const InputDecoration(
                  hintText:
                      'Nombre,Descripcion,Tipo,Puntos\nPrimera sangre,Hacer el primer daño,Una vez por ronda,1\nRendirse,Conceder la partida,Una vez por jugador,-1'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _text.text),
            child: const Text('Revisar')),
      ],
    );
  }
}
