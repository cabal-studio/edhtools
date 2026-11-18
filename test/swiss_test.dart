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
}
