// Lógica pura del torneo: puntos, desempates y emparejamiento suizo en mesas.
// Sin dependencias de Flutter/Firebase para poder probarla con `dart test`.
import 'dart:math';

int asInt(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;
num asNum(dynamic v, [num d = 0]) => v is num ? v : d;

/// Resultados posibles de un jugador en una mesa.
const kResultLabels = {
  'W': 'Gana',
  '2': '2º',
  '3': '3º',
  'D': 'Empate',
  'L': 'Pierde',
};

class Points {
  final num win, draw, loss, p2, p3, bye;
  const Points({
    this.win = 5,
    this.draw = 1,
    this.loss = 0,
    this.p2 = 0,
    this.p3 = 0,
    this.bye = 5,
  });

  bool get usesPlacement => p2 > 0 || p3 > 0;

  factory Points.fromMap(Map<String, dynamic>? m) {
    m ??= const {};
    return Points(
      win: asNum(m['win'], 5),
      draw: asNum(m['draw'], 1),
      loss: asNum(m['loss'], 0),
      p2: asNum(m['p2'], 0),
      p3: asNum(m['p3'], 0),
      bye: asNum(m['bye'], 5),
    );
  }

  Map<String, dynamic> toMap() =>
      {'win': win, 'draw': draw, 'loss': loss, 'p2': p2, 'p3': p3, 'bye': bye};

  num forResult(String? r) {
    switch (r) {
      case 'W':
        return win;
      case '2':
        return p2;
      case '3':
        return p3;
      case 'D':
        return draw;
      case 'L':
        return loss;
      default:
        return 0;
    }
  }
}

class PlayerData {
  final String id;
  final String nick;

  /// Cuenta de la app que usa este jugador (null si lo agregó el organizador).
  final String? uid;
  final bool dropped;
  final int joinedAt;

  /// Si la cuenta es de Google (la informa el propio jugador al inscribirse).
  final bool google;

  /// Ficha del jugador en el mantenedor del organizador (jugadores manuales).
  final String? rosterId;
  const PlayerData(
      {required this.id,
      required this.nick,
      this.uid,
      this.dropped = false,
      this.joinedAt = 0,
      this.google = false,
      this.rosterId});

  /// Ficha en el mantenedor: la cuenta para jugadores con app, o la ficha manual.
  String? get rosterKey => uid ?? rosterId;

  factory PlayerData.fromMap(String id, Map<String, dynamic> m) => PlayerData(
        id: id,
        nick: (m['nick'] as String?) ?? '¿?',
        uid: m['uid'] as String?,
        dropped: m['dropped'] == true,
        joinedAt: asInt(m['joinedAt']),
        google: m['google'] == true,
        rosterId: m['rosterId'] as String?,
      );
}

class TableData {
  final int t;
  final List<String> seats;
  final Map<String, String> res;
  TableData({required this.t, required this.seats, Map<String, String>? res})
      : res = res ?? {};

  bool get complete => seats.every((p) => res[p] != null);

  factory TableData.fromMap(Map<String, dynamic> m) => TableData(
        t: asInt(m['t']),
        seats: List<String>.from(m['seats'] ?? const []),
        res: Map<String, String>.from(m['res'] ?? const {}),
      );

  Map<String, dynamic> toMap() => {'t': t, 'seats': seats, 'res': res};

  TableData copy() =>
      TableData(t: t, seats: List.of(seats), res: Map.of(res));
}

class RoundData {
  final int n;
  final List<TableData> tables;
  final List<String> byes;
  final bool confirmed;
  final int repeats;

  /// Preguntas de votación especial activas en esta ronda.
  final List<String> voteQuestions;
  RoundData(
      {required this.n,
      required this.tables,
      this.byes = const [],
      this.confirmed = false,
      this.repeats = 0,
      this.voteQuestions = const []});

  factory RoundData.fromMap(Map<String, dynamic> m) => RoundData(
        n: asInt(m['n']),
        tables: ((m['tables'] as List?) ?? const [])
            .map((e) => TableData.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        byes: List<String>.from(m['byes'] ?? const []),
        confirmed: m['confirmed'] == true,
        repeats: asInt(m['repeats']),
        voteQuestions: List<String>.from(m['voteQuestions'] ?? const []),
      );

  /// `seatOf` permite a las reglas de Firestore validar que quien reporta
  /// o vota realmente está sentado en esa mesa.
  Map<String, dynamic> toMap() => {
        'n': n,
        'tables': tables.map((t) => t.toMap()).toList(),
        'byes': byes,
        'confirmed': confirmed,
        'repeats': repeats,
        'voteQuestions': voteQuestions,
        'seatOf': seatOfTables(tables),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };

  RoundData copyWith({
    List<TableData>? tables,
    List<String>? byes,
    bool? confirmed,
    int? repeats,
    List<String>? voteQuestions,
  }) =>
      RoundData(
        n: n,
        tables: tables ?? this.tables,
        byes: byes ?? this.byes,
        confirmed: confirmed ?? this.confirmed,
        repeats: repeats ?? this.repeats,
        voteQuestions: voteQuestions ?? this.voteQuestions,
      );

  RoundData withConfirmed(bool c) => copyWith(confirmed: c);

  /// Todos los jugadores con asiento o bye en esta ronda.
  Set<String> get seated => {
        for (final t in tables) ...t.seats,
        ...byes,
      };

  /// Mesa del jugador, o null si no tiene mesa (bye o sin asignar).
  TableData? tableOf(String pid) {
    for (final t in tables) {
      if (t.seats.contains(pid)) return t;
    }
    return null;
  }
}

Map<String, int> seatOfTables(List<TableData> tables) => {
      for (final tb in tables)
        for (final p in tb.seats) p: tb.t
    };

/// Cantidad de pares de jugadores que ya se enfrentaron en rondas anteriores.
int countRepeats(List<RoundData> prev, List<TableData> tables) {
  String key(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  final met = <String>{};
  for (final r in prev) {
    for (final tb in r.tables) {
      for (var i = 0; i < tb.seats.length; i++) {
        for (var j = i + 1; j < tb.seats.length; j++) {
          met.add(key(tb.seats[i], tb.seats[j]));
        }
      }
    }
  }
  var rep = 0;
  for (final tb in tables) {
    for (var i = 0; i < tb.seats.length; i++) {
      for (var j = i + 1; j < tb.seats.length; j++) {
        if (met.contains(key(tb.seats[i], tb.seats[j]))) rep++;
      }
    }
  }
  return rep;
}

/// Edición manual de mesas en la preparación de una ronda.
/// Mueve [pid] a la posición de [targetPid] (intercambiándolos), o al final
/// de la mesa [toTable], o a los byes si [toBye]. Limpia los resultados de
/// las mesas tocadas. Devuelve las nuevas mesas y byes; elimina mesas vacías
/// y renumera desde 1.
({List<TableData> tables, List<String> byes}) movePlayer(
  List<TableData> tables,
  List<String> byes, {
  required String pid,
  String? targetPid,
  int? toTable,
  bool toBye = false,
}) {
  final ts = tables.map((t) => t.copy()).toList();
  final bs = List.of(byes);
  if (pid == targetPid) return (tables: ts, byes: bs);

  // Ubicación (lista + índice) de un jugador: en una mesa o en los byes.
  ({List<String> list, int i, TableData? table})? where(String who) {
    for (final t in ts) {
      final i = t.seats.indexOf(who);
      if (i >= 0) return (list: t.seats, i: i, table: t);
    }
    final i = bs.indexOf(who);
    if (i >= 0) return (list: bs, i: i, table: null);
    return null;
  }

  final from = where(pid);
  if (targetPid != null) {
    final to = where(targetPid);
    if (to == null) return (tables: ts, byes: bs);
    if (from != null) {
      // Intercambio: cada uno ocupa el lugar del otro.
      from.list[from.i] = targetPid;
      from.table?.res.clear();
    }
    to.list[to.i] = pid;
    to.table?.res.clear();
  } else {
    if (from != null) {
      from.list.removeAt(from.i);
      from.table?.res.clear();
    }
    if (toBye) {
      bs.add(pid);
    } else if (toTable != null) {
      final t = ts.where((x) => x.t == toTable).toList();
      if (t.isNotEmpty) {
        t.first.seats.add(pid);
        t.first.res.clear();
      } else {
        ts.add(TableData(t: toTable, seats: [pid]));
      }
    }
  }
  final kept = ts.where((t) => t.seats.isNotEmpty).toList();
  return (
    tables: [
      for (var i = 0; i < kept.length; i++)
        TableData(t: i + 1, seats: kept[i].seats, res: kept[i].res)
    ],
    byes: bs,
  );
}

class Standing {
  final String id;
  String nick = '¿?';
  bool dropped = false;
  num pts = 0;
  int played = 0, w = 0, d = 0, l = 0, byes = 0, rank = 0;
  final List<String> opps = [];
  double mw = 0, omw = 0, oomw = 0;
  Standing(this.id);
}

/// Desempates clásicos MTG adaptados a mesas multijugador:
///  1) Puntos
///  2) OMW%  – promedio del % de victoria de tus oponentes (mínimo 33%)
///  3) MW%   – tu propio %; equivale a GW% (cada ronda es una sola partida)
///  4) OOMW% – promedio del OMW% de tus oponentes; equivale a OGW%
List<Standing> computeStandings(
    List<RoundData> rounds, Map<String, PlayerData> players, Points p) {
  final st = <String, Standing>{};
  Standing en(String id) => st.putIfAbsent(id, () => Standing(id));
  for (final id in players.keys) {
    en(id);
  }
  for (final r in rounds) {
    for (final tb in r.tables) {
      for (final pid in tb.seats) {
        final s = en(pid);
        final v = tb.res[pid];
        s.pts += p.forResult(v);
        s.played++;
        if (v == 'W') {
          s.w++;
        } else if (v == 'D') {
          s.d++;
        } else if (v != null) {
          s.l++;
        }
        for (final o in tb.seats) {
          if (o != pid) s.opps.add(o);
        }
      }
    }
    for (final pid in r.byes) {
      final s = en(pid);
      s.pts += p.bye;
      s.played++;
      s.byes++;
    }
  }
  const floor = 0.33;
  final maxW = max(1, p.win.toDouble());
  double avg(Iterable<double> a) =>
      a.isEmpty ? 0 : a.reduce((x, y) => x + y) / a.length;
  for (final s in st.values) {
    s.mw = s.played == 0
        ? floor
        : (s.pts / (s.played * maxW)).clamp(floor, 1.0).toDouble();
  }
  for (final s in st.values) {
    s.omw = avg(s.opps.map((o) => st[o]?.mw ?? floor));
  }
  for (final s in st.values) {
    s.oomw = avg(s.opps.map((o) => st[o]?.omw ?? 0));
    s.nick = players[s.id]?.nick ?? '¿?';
    s.dropped = players[s.id]?.dropped ?? false;
  }
  int cmpD(double a, double b) =>
      (b - a).abs() < 1e-9 ? 0 : (b > a ? 1 : -1);
  final out = st.values.toList()
    ..sort((a, b) {
      final c1 = b.pts.compareTo(a.pts);
      if (c1 != 0) return c1;
      final c2 = cmpD(a.omw, b.omw);
      if (c2 != 0) return c2;
      final c3 = cmpD(a.mw, b.mw);
      if (c3 != 0) return c3;
      final c4 = cmpD(a.oomw, b.oomw);
      if (c4 != 0) return c4;
      return a.nick.compareTo(b.nick);
    });
  for (var i = 0; i < out.length; i++) {
    out[i].rank = i + 1;
  }
  return out;
}

/// Tamaños de mesa: todas de 4 y las últimas de 3. Con 5 jugadores: 4 + bye.
({List<int> sizes, int byes}) podSizes(int n) {
  if (n < 3) return (sizes: <int>[], byes: n);
  final threes = (4 - n % 4) % 4;
  if (threes * 3 > n) return (sizes: [4], byes: n - 4); // n = 5
  final fours = (n - threes * 3) ~/ 4;
  return (
    sizes: [...List.filled(fours, 4), ...List.filled(threes, 3)],
    byes: 0
  );
}

int suggestedRounds(int n) => n <= 8
    ? 3
    : n <= 16
        ? 4
        : n <= 32
            ? 5
            : n <= 64
                ? 6
                : 7;

RoundData buildRound(int n, List<RoundData> prev,
    Map<String, PlayerData> players, Points p,
    {Random? rng}) {
  final rnd = rng ?? Random();
  final active =
      players.values.where((x) => !x.dropped).map((x) => x.id).toList();
  final stand = computeStandings(prev, players, p);
  final ptsOf = {for (final s in stand) s.id: s.pts};
  final first = prev.isEmpty;

  // Orden por puntos; aleatorio dentro de cada grupo de puntos (suizo).
  final order = List.of(active)..shuffle(rnd);
  if (!first) {
    // sort estable: List.sort no lo garantiza, así que usamos índice.
    final idx = {for (var i = 0; i < order.length; i++) order[i]: i};
    order.sort((a, b) {
      final c = (ptsOf[b] ?? 0).compareTo(ptsOf[a] ?? 0);
      return c != 0 ? c : idx[a]!.compareTo(idx[b]!);
    });
  }

  final met = <String>{};
  final hadBye = <String>{};
  String key(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  for (final r in prev) {
    for (final tb in r.tables) {
      for (var i = 0; i < tb.seats.length; i++) {
        for (var j = i + 1; j < tb.seats.length; j++) {
          met.add(key(tb.seats[i], tb.seats[j]));
        }
      }
    }
    hadBye.addAll(r.byes);
  }

  final ps = podSizes(order.length);
  final byes = <String>[];
  for (var k = 0; k < ps.byes; k++) {
    var i = order.length - 1;
    while (i >= 0 && hadBye.contains(order[i])) {
      i--;
    }
    if (i < 0) i = order.length - 1;
    byes.add(order.removeAt(i));
  }

  num pen(List<String> pod) {
    var rep = 0;
    for (var i = 0; i < pod.length; i++) {
      for (var j = i + 1; j < pod.length; j++) {
        if (met.contains(key(pod[i], pod[j]))) rep++;
      }
    }
    final pts = pod.map((x) => ptsOf[x] ?? 0);
    return rep * 1000 + (pts.reduce(max) - pts.reduce(min));
  }

  List<List<String>> build(List<String> ord) {
    final out = <List<String>>[];
    var k = 0;
    for (final s in ps.sizes) {
      out.add(ord.sublist(k, k + s));
      k += s;
    }
    return out;
  }

  /// Mejora local: intercambia jugadores entre mesas si no empeora.
  num climb(List<List<String>> pods) {
    for (var it = 0; it < 4000; it++) {
      final i = rnd.nextInt(pods.length);
      final j = rnd.nextInt(pods.length);
      if (i == j) continue;
      final a = pods[i], b = pods[j];
      final ai = rnd.nextInt(a.length), bi = rnd.nextInt(b.length);
      final before = pen(a) + pen(b);
      final tmp = a[ai];
      a[ai] = b[bi];
      b[bi] = tmp;
      if (pen(a) + pen(b) > before) {
        b[bi] = a[ai];
        a[ai] = tmp;
      }
    }
    return pods.fold<num>(0, (s, p) => s + pen(p));
  }

  var pods = build(order);
  if (!first && pods.length > 1) {
    // Varios reinicios: el primero respeta el orden por puntos; los demás
    // reordenan al azar dentro de cada grupo de puntos. Se queda el mejor.
    var best = pods;
    var bestPen = climb(pods);
    for (var rs = 1; rs < 25 && bestPen >= 1000; rs++) {
      final ord = List.of(order)..shuffle(rnd);
      final idx = {for (var i = 0; i < ord.length; i++) ord[i]: i};
      ord.sort((a, b) {
        final c = (ptsOf[b] ?? 0).compareTo(ptsOf[a] ?? 0);
        return c != 0 ? c : idx[a]!.compareTo(idx[b]!);
      });
      final cand = build(ord);
      final cp = climb(cand);
      if (cp < bestPen) {
        best = cand;
        bestPen = cp;
      }
    }
    pods = best;
  }

  double avgP(List<String> pod) =>
      pod.fold<num>(0, (s, x) => s + (ptsOf[x] ?? 0)) / pod.length;
  pods.sort((x, y) {
    final c = y.length.compareTo(x.length);
    return c != 0 ? c : avgP(y).compareTo(avgP(x));
  });
  var repeats = 0;
  for (final pod in pods) {
    repeats += pen(pod) ~/ 1000;
  }

  return RoundData(
    n: n,
    tables: [
      for (var i = 0; i < pods.length; i++)
        TableData(t: i + 1, seats: List.of(pods[i])..shuffle(rnd))
    ],
    byes: byes,
    repeats: repeats,
  );
}

/// Marca un resultado; si se marca "Gana" y no hay puntos por posición,
/// el resto de la mesa queda como "Pierde".
void applyPick(Map<String, String> res, List<String> seats, String pid,
    String v, Points p) {
  if (res[pid] == v) {
    res.remove(pid);
    return;
  }
  res[pid] = v;
  if (v == 'W') {
    for (final o in seats) {
      if (o == pid) continue;
      if (res[o] == 'W' || (!p.usesPlacement && res[o] == null)) res[o] = 'L';
    }
  }
}
