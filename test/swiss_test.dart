import 'dart:math';

import 'package:edhtools/logic/swiss.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, PlayerData> makePlayers(int n) => {
      for (var i = 0; i < n; i++)
        'p$i': PlayerData(id: 'p$i', nick: 'Jugador $i', joinedAt: i)
    };

void main() {
  test('tamaños de mesa: de 4 y las de 3 al final', () {
    expect(podSizes(3).sizes, [3]);
    expect(podSizes(5).sizes, [4]);
    expect(podSizes(5).byes, 1);
    expect(podSizes(6).sizes, [3, 3]);
    expect(podSizes(7).sizes, [4, 3]);
    expect(podSizes(13).sizes, [4, 3, 3, 3]);
    expect(podSizes(22).sizes, [4, 4, 4, 4, 3, 3]);
    for (var n = 6; n <= 64; n++) {
      final s = podSizes(n);
      expect(s.sizes.fold<int>(0, (a, b) => a + b) + s.byes, n);
      expect(s.byes, 0);
    }
  });

  test('16 jugadores: rondas 2 y 3 sin repetir oponentes', () {
    final rng = Random(7);
    final ps = makePlayers(16);
    const p = Points();
    final rounds = <RoundData>[];
    for (var n = 1; n <= 4; n++) {
      final r = buildRound(n, rounds, ps, p, rng: rng);
      if (n <= 3) expect(r.repeats, 0, reason: 'ronda $n');
      for (final tb in r.tables) {
        final w = tb.seats[rng.nextInt(tb.seats.length)];
        for (final s in tb.seats) {
          tb.res[s] = s == w ? 'W' : 'L';
        }
      }
      rounds.add(r.withConfirmed(true));
    }
    // En la ronda 4 algunas repeticiones son inevitables con 16 jugadores.
    final total = rounds.fold<int>(0, (a, r) => a + r.repeats);
    expect(total, lessThanOrEqualTo(6));
    final st = computeStandings(rounds, ps, p);
    expect(st.length, 16);
    expect(st.first.pts >= st.last.pts, true);
    for (final s in st) {
      expect(s.omw, greaterThanOrEqualTo(0.33));
    }
  });

  test('drop excluido del emparejamiento', () {
    final ps = makePlayers(8);
    ps['p0'] = const PlayerData(id: 'p0', nick: 'Drop', dropped: true);
    final r = buildRound(1, const [], ps, const Points());
    expect(r.tables.expand((t) => t.seats).contains('p0'), false);
    expect(r.tables.map((t) => t.seats.length).toList(), [4, 3]);
  });

  group('edición manual de mesas', () {
    List<TableData> mesas() => [
          TableData(t: 1, seats: ['a', 'b', 'c', 'd'], res: {'a': 'W'}),
          TableData(t: 2, seats: ['e', 'f', 'g']),
        ];

    test('intercambiar jugadores entre mesas', () {
      final r = movePlayer(mesas(), [], pid: 'a', targetPid: 'e');
      expect(r.tables[0].seats, ['e', 'b', 'c', 'd']);
      expect(r.tables[1].seats, ['a', 'f', 'g']);
      expect(r.tables[0].res, isEmpty, reason: 'se limpian resultados');
    });

    test('intercambiar dentro de la misma mesa (orden de asiento)', () {
      final r = movePlayer(mesas(), [], pid: 'd', targetPid: 'a');
      expect(r.tables[0].seats, ['d', 'b', 'c', 'a']);
    });

    test('mover a otra mesa y a bye', () {
      var r = movePlayer(mesas(), [], pid: 'd', toTable: 2);
      expect(r.tables[0].seats, ['a', 'b', 'c']);
      expect(r.tables[1].seats, ['e', 'f', 'g', 'd']);
      r = movePlayer(r.tables, r.byes, pid: 'g', toBye: true);
      expect(r.byes, ['g']);
      r = movePlayer(r.tables, r.byes, pid: 'g', targetPid: 'a');
      expect(r.byes, ['a']);
      expect(r.tables[0].seats.first, 'g');
    });

    test('mesa vacía se elimina y se renumera', () {
      var r = movePlayer(mesas(), [], pid: 'e', toTable: 1);
      r = movePlayer(r.tables, r.byes, pid: 'f', toTable: 1);
      r = movePlayer(r.tables, r.byes, pid: 'g', toTable: 3);
      expect(r.tables.map((t) => t.t), [1, 2]);
      expect(r.tables[1].seats, ['g']);
    });

    test('jugador sin mesa toma el lugar de otro', () {
      final r = movePlayer(mesas(), [], pid: 'z', targetPid: 'b');
      expect(r.tables[0].seats, ['a', 'z', 'c', 'd']);
      expect([...r.tables[0].seats, ...r.tables[1].seats].contains('b'), false);
    });

    test('contar repeticiones', () {
      final prev = [RoundData(n: 1, tables: mesas(), confirmed: true)];
      final nuevas = [
        TableData(t: 1, seats: ['a', 'b', 'e', 'f']),
        TableData(t: 2, seats: ['c', 'd', 'g']),
      ];
      // a-b, e-f y c-d ya jugaron juntos.
      expect(countRepeats(prev, nuevas), 3);
    });
  });
}
