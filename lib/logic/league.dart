// Lógica pura de la Liga: logros, puntaje por ronda, puntajes máximos,
// desempates configurables y armado de mesas (aleatorio, suizo o con líderes).
// Sin dependencias de Flutter/Firebase para poder probarla.
import 'dart:math';

import 'swiss.dart';

/// Tipos de logro.
///  * auto:      cada jugador lo recibe al comenzar la ronda
///  * player:    cada jugador puede reclamarlo una vez por ronda
///  * round:     solo un jugador puede reclamarlo por ronda
///  * unlimited: se puede reclamar cuantas veces se quiera
enum AchType { auto, player, round, unlimited }

const kAchTypeLabels = {
  AchType.auto: 'Automático',
  AchType.player: 'Una vez por jugador',
  AchType.round: 'Una vez por ronda',
  AchType.unlimited: 'Sin límite',
};

AchType achTypeFrom(dynamic v) => switch (v) {
      'auto' => AchType.auto,
      'round' => AchType.round,
      'unlimited' => AchType.unlimited,
      _ => AchType.player,
    };

class Achievement {
  final String id;
  final String name;
  final String description;
  final AchType type;

  /// Puntos que suma el logro (pueden ser negativos: restan al puntaje).
  final num points;
  const Achievement({
    required this.id,
    required this.name,
    this.description = '',
    this.type = AchType.player,
    this.points = 1,
  });

  factory Achievement.fromMap(String id, Map<String, dynamic> m) => Achievement(
        id: id,
        name: (m['name'] as String?) ?? '¿?',
        description: (m['description'] as String?) ?? '',
        type: achTypeFrom(m['type']),
        points: asNum(m['points'], 0),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'type': type.name,
        'points': points,
      };

  Achievement copyWith({
    String? name,
    String? description,
    AchType? type,
    num? points,
  }) =>
      Achievement(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        type: type ?? this.type,
        points: points ?? this.points,
      );
}

/// Un logro obtenido por un jugador en una ronda.
class Claim {
  final String id;
  final int round;
  final String pid;
  final String ach;
  final int at;
  const Claim(
      {required this.id,
      required this.round,
      required this.pid,
      required this.ach,
      this.at = 0});
  factory Claim.fromMap(String id, Map<String, dynamic> m) => Claim(
        id: id,
        round: asInt(m['round']),
        pid: (m['pid'] as String?) ?? '',
        ach: (m['ach'] as String?) ?? '',
        at: asInt(m['at']),
      );
}

/// Id del documento de un reclamo. Las reglas de Firestore usan este mismo
/// formato para hacer cumplir el tipo de logro:
///  * player / auto: r{n}-{logro}-{jugador}   (uno por jugador)
///  * round:         r{n}-{logro}             (uno por ronda)
///  * unlimited:     r{n}-{logro}-{jugador}-{aleatorio}
String claimId(Achievement a, int round, String pid, {String? suffix}) {
  final base = 'r$round-${a.id}';
  return switch (a.type) {
    AchType.round => base,
    AchType.unlimited => '$base-$pid-${suffix ?? _rand()}',
    _ => '$base-$pid',
  };
}

String _rand() {
  const al = 'abcdefghijkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(8, (_) => al[r.nextInt(al.length)]).join();
}

/// Id seguro para un logro (letras y números, sin guiones).
String achIdFromName(String name, Set<String> taken) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  var base = name.toLowerCase().split('').map((c) {
    final i = from.indexOf(c);
    return i >= 0 ? to[i] : c;
  }).join();
  base = base.replaceAll(RegExp('[^a-z0-9]'), '');
  if (base.isEmpty) base = 'logro';
  if (base.length > 24) base = base.substring(0, 24);
  var id = base;
  var k = 2;
  while (taken.contains(id)) {
    id = '$base$k';
    k++;
  }
  return id;
}

// ----------------------------------------------------------------- CSV
class CsvResult {
  final List<Achievement> items;
  final List<String> errors;
  CsvResult(this.items, this.errors);
}

AchType? _parseType(String s) {
  final t = s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úù]'), 'u')
      .replaceAll(RegExp('[^a-z]'), '');
  if (t.isEmpty) return AchType.player;
  if (t.startsWith('auto')) return AchType.auto;
  if (t.contains('jugador') || t == 'player') return AchType.player;
  if (t.contains('ronda') || t == 'round') return AchType.round;
  if (t.contains('limite') || t.contains('ilimitado') || t == 'unlimited') {
    return AchType.unlimited;
  }
  return null;
}

List<List<String>> _csvRows(String text, String sep) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQ = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQ) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      inQ = true;
    } else if (c == sep) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((x) => x.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((x) => x.isNotEmpty)) rows.add(row);
  return rows;
}

/// Lee logros desde CSV con columnas: Nombre, Descripcion, Tipo, Puntos.
/// (Una quinta columna, de versiones anteriores, se ignora.)
/// Acepta coma o punto y coma como separador y una fila de encabezado opcional.
/// Tipo: Automático | Una vez por jugador | Una vez por ronda | Sin límite.
CsvResult parseAchievementsCsv(String text, {Set<String> takenIds = const {}}) {
  final clean = text.replaceFirst('﻿', '');
  final firstLine = clean.split(RegExp(r'\r?\n')).first;
  final sep = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
      ? ';'
      : ',';
  final rows = _csvRows(clean, sep);
  final items = <Achievement>[];
  final errors = <String>[];
  final taken = {...takenIds};
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final line = i + 1;
    if (i == 0 && r.isNotEmpty && r[0].toLowerCase().startsWith('nombre')) {
      continue; // encabezado
    }
    String col(int k) => k < r.length ? r[k] : '';
    final name = col(0);
    if (name.isEmpty) {
      errors.add('Fila $line: falta el nombre');
      continue;
    }
    final type = _parseType(col(2));
    if (type == null) {
      errors.add('Fila $line ("$name"): tipo "${col(2)}" no reconocido');
      continue;
    }
    num? parseNum(String s) =>
        s.isEmpty ? 0 : num.tryParse(s.replaceAll(',', '.'));
    final pts = parseNum(col(3));
    if (pts == null) {
      errors.add('Fila $line ("$name"): los puntos no son un número');
      continue;
    }
    final id = achIdFromName(name, taken);
    taken.add(id);
    items.add(Achievement(
        id: id,
        name: name,
        description: col(1),
        type: type,
        points: pts));
  }
  return CsvResult(items, errors);
}

String achievementsToCsv(List<Achievement> list) {
  String q(String s) =>
      s.contains(RegExp('[",;\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  final b = StringBuffer('Nombre,Descripcion,Tipo,Puntos\n');
  for (final a in list) {
    b.writeln([
      q(a.name),
      q(a.description),
      kAchTypeLabels[a.type]!,
      '${a.points}',
    ].join(','));
  }
  return b.toString();
}

// ----------------------------------------------------------- standings
/// Claves de desempate configurables:
///  'omw', 'mw', 'oomw', 'wins', 'achPos' (logros positivos obtenidos, más
///  es mejor), 'achNeg' (logros negativos obtenidos, menos es mejor) y
///  'ach:{id}' (veces que obtuvo ese logro).
String tiebreakLabel(String key, Map<String, Achievement> achs) {
  if (key.startsWith('ach:')) {
    return 'Logro: ${achs[key.substring(4)]?.name ?? '¿?'}';
  }
  return switch (key) {
    'omw' => 'OMW% (rivales)',
    'mw' => 'MW% (propio)',
    'oomw' => 'OOMW% (rivales de rivales)',
    'wins' => 'Victorias',
    'achPos' => 'Cantidad de logros positivos',
    'achNeg' => 'Cantidad de logros negativos (menos es mejor)',
    _ => key,
  };
}

const kDefaultTiebreakers = ['omw', 'mw', 'oomw'];

class LeagueStanding {
  final String id;
  String nick = '¿?';
  bool dropped = false;

  /// Puntaje que cuenta para el standing (suma o mejores N rondas).
  num total = 0;

  /// Suma de todas las rondas (aunque se usen puntajes máximos).
  num allPoints = 0;
  final Map<int, num> roundScores = {};

  /// Rondas cuyo puntaje cuenta (con puntajes máximos).
  final Set<int> counted = {};
  int wins = 0;
  double omw = 0, mw = 0, oomw = 0;
  final Map<String, int> achCounts = {};

  /// Cantidad de logros obtenidos con puntos positivos / negativos.
  int achPos = 0, achNeg = 0;
  int rank = 0;
  LeagueStanding(this.id);

  int get roundsPlayed => roundScores.length;

  num tiebreak(String key) => switch (key) {
        'omw' => omw,
        'mw' => mw,
        'oomw' => oomw,
        'wins' => wins,
        'achPos' => achPos,
        // Menos logros negativos es mejor: se invierte para ordenar.
        'achNeg' => -achNeg,
        _ when key.startsWith('ach:') => achCounts[key.substring(4)] ?? 0,
        _ => 0,
      };
}

/// Puntaje de cada jugador en una ronda: resultado de mesa (o bye) +
/// puntos de logros (que pueden ser negativos).
Map<String, num> leagueRoundScores(RoundData r, Points pts,
    Map<String, Achievement> achs, Iterable<Claim> claims) {
  final out = <String, num>{};
  for (final tb in r.tables) {
    for (final p in tb.seats) {
      out[p] = (out[p] ?? 0) + pts.forResult(tb.res[p]);
    }
  }
  for (final p in r.byes) {
    out[p] = (out[p] ?? 0) + pts.bye;
  }
  for (final c in claims.where((c) => c.round == r.n)) {
    final a = achs[c.ach];
    if (a == null) continue;
    out[c.pid] = (out[c.pid] ?? 0) + a.points;
  }
  return out;
}

/// [claims] null = el espectador no puede ver los logros: se usan los
/// puntajes y conteos que el organizador guardó en cada ronda confirmada.
List<LeagueStanding> computeLeagueStandings({
  required List<RoundData> rounds,
  required Map<String, PlayerData> players,
  required Points pts,
  Map<String, Achievement> achievements = const {},
  Iterable<Claim>? claims = const [],
  List<String> tiebreakers = kDefaultTiebreakers,
  int maxScores = 0,
}) {
  final base = {
    for (final s in computeStandings(rounds, players, pts)) s.id: s,
  };
  final st = <String, LeagueStanding>{};
  LeagueStanding en(String id) => st.putIfAbsent(id, () => LeagueStanding(id));
  for (final id in players.keys) {
    en(id);
  }
  for (final r in rounds) {
    final scores = claims == null && r.scores != null
        ? r.scores!
        : leagueRoundScores(r, pts, achievements, claims ?? const []);
    scores.forEach((pid, v) => en(pid).roundScores[r.n] = v);
    if (claims == null) {
      r.achTb?.forEach((pid, m) {
        final s = en(pid);
        m.forEach((a, k) => s.achCounts[a] = (s.achCounts[a] ?? 0) + k);
      });
    }
  }
  if (claims != null) {
    final roundNs = rounds.map((r) => r.n).toSet();
    for (final c in claims.where((c) => roundNs.contains(c.round))) {
      final s = en(c.pid);
      s.achCounts[c.ach] = (s.achCounts[c.ach] ?? 0) + 1;
    }
  }
  for (final s in st.values) {
    final b = base[s.id];
    if (b != null) {
      s.omw = b.omw;
      s.mw = b.mw;
      s.oomw = b.oomw;
      s.wins = b.w;
    }
    s.achCounts.forEach((id, k) {
      final p = achievements[id]?.points ?? 0;
      if (p > 0) s.achPos += k;
      if (p < 0) s.achNeg += k;
    });
    s.nick = players[s.id]?.nick ?? '¿?';
    s.dropped = players[s.id]?.dropped ?? false;
    s.allPoints = s.roundScores.values.fold<num>(0, (a, b) => a + b);
    final entries = s.roundScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final take = maxScores > 0 && maxScores < entries.length
        ? entries.take(maxScores)
        : entries;
    s.counted.addAll(take.map((e) => e.key));
    s.total = take.fold<num>(0, (a, e) => a + e.value);
  }
  int cmp(num a, num b) => (b - a).abs() < 1e-9 ? 0 : (b > a ? 1 : -1);
  final out = st.values.toList()
    ..sort((a, b) {
      // Quien no ha jugado ninguna ronda va al final (no ocupa puestos).
      if (rounds.isNotEmpty && (a.roundsPlayed > 0) != (b.roundsPlayed > 0)) {
        return a.roundsPlayed > 0 ? -1 : 1;
      }
      final c = cmp(a.total, b.total);
      if (c != 0) return c;
      for (final k in tiebreakers) {
        final d = cmp(a.tiebreak(k), b.tiebreak(k));
        if (d != 0) return d;
      }
      return a.nick.compareTo(b.nick);
    });
  for (var i = 0; i < out.length; i++) {
    out[i].rank = i + 1;
  }
  return out;
}

// ------------------------------------------------------------- mesas
enum PairingMode { random, leaders, swiss }

const kPairingLabels = {
  PairingMode.random: 'Aleatorio',
  PairingMode.leaders: 'Aleatorio con líderes',
  PairingMode.swiss: 'Suizo (por puntos)',
};

PairingMode pairingFrom(dynamic v) => switch (v) {
      'leaders' => PairingMode.leaders,
      'swiss' => PairingMode.swiss,
      _ => PairingMode.random,
    };

/// Arma las mesas de una ronda de liga con los inscritos [participants].
/// [order] es el standing actual (mejor primero) para líderes y suizo.
/// Con líderes: los 3 primeros quedan en mesas distintas y en orden inverso
/// (líder 1 → mesa 3, líder 2 → mesa 2, líder 3 → mesa 1). Si hay 2 mesas,
/// los líderes 1 y 2 van juntos en la mesa 2 y el 3 en la mesa 1.
RoundData buildLeagueRound({
  required int n,
  required List<String> participants,
  required PairingMode mode,
  required List<String> order,
  required List<RoundData> prevRounds,
  required Map<String, PlayerData> players,
  required Points pts,
  Random? rng,
}) {
  final rnd = rng ?? Random();
  if (mode == PairingMode.swiss) {
    final sub = {
      for (final p in participants)
        p: players[p] ?? PlayerData(id: p, nick: '¿?'),
    };
    // Solo los inscritos de esta ronda, sin drop.
    final active = {
      for (final e in sub.entries) e.key: PlayerData(
          id: e.value.id, nick: e.value.nick, uid: e.value.uid, dropped: false)
    };
    return buildRound(n, prevRounds, active, pts, rng: rnd);
  }

  final hadBye = {for (final r in prevRounds) ...r.byes};
  final ps = podSizes(participants.length);
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  final sorted = List.of(participants)
    ..sort((a, b) => (rank[a] ?? 1 << 20).compareTo(rank[b] ?? 1 << 20));
  final leaders = mode == PairingMode.leaders
      ? sorted.take(min(3, sorted.length)).toList()
      : <String>[];
  final others = participants.where((p) => !leaders.contains(p)).toList()
    ..shuffle(rnd);

  // Byes: entre los no líderes, prefiriendo a quien no ha tenido bye.
  final byes = <String>[];
  for (var k = 0; k < ps.byes; k++) {
    final pool = others.isNotEmpty ? others : leaders;
    var pick = pool.lastWhere((p) => !hadBye.contains(p),
        orElse: () => pool.last);
    pool.remove(pick);
    byes.add(pick);
  }

  final pods = [for (final _ in ps.sizes) <String>[]];
  if (leaders.isNotEmpty && pods.isNotEmpty) {
    final k = pods.length;
    if (k >= 3) {
      pods[2].add(leaders[0]);
      if (leaders.length > 1) pods[1].add(leaders[1]);
      if (leaders.length > 2) pods[0].add(leaders[2]);
    } else if (k == 2) {
      pods[1].addAll(leaders.take(2));
      if (leaders.length > 2) pods[0].add(leaders[2]);
    } else {
      pods[0].addAll(leaders);
    }
  }
  var oi = 0;
  for (var i = 0; i < pods.length; i++) {
    while (pods[i].length < ps.sizes[i] && oi < others.length) {
      pods[i].add(others[oi++]);
    }
  }
  final tables = [
    for (var i = 0; i < pods.length; i++)
      TableData(t: i + 1, seats: List.of(pods[i])..shuffle(rnd))
  ];
  return RoundData(
    n: n,
    tables: tables,
    byes: byes,
    repeats: countRepeats(prevRounds, tables),
  );
}

/// Lo que el organizador guarda en una ronda confirmada de liga.
({Map<String, num> scores, Map<String, Map<String, int>> achTb}) storedRoundData(
    RoundData r,
    Points pts,
    Map<String, Achievement> achs,
    Iterable<Claim> claims,
    List<String> tiebreakers) {
  final scores = leagueRoundScores(r, pts, achs, claims);
  final tbAchs = {
    ...tiebreakers.where((k) => k.startsWith('ach:')).map((k) => k.substring(4)),
    if (tiebreakers.contains('achPos'))
      ...achs.values.where((a) => a.points > 0).map((a) => a.id),
    if (tiebreakers.contains('achNeg'))
      ...achs.values.where((a) => a.points < 0).map((a) => a.id),
  };
  final achTb = <String, Map<String, int>>{};
  for (final c in claims.where((c) => c.round == r.n && tbAchs.contains(c.ach))) {
    final m = achTb.putIfAbsent(c.pid, () => {});
    m[c.ach] = (m[c.ach] ?? 0) + 1;
  }
  return (scores: scores, achTb: achTb);
}
