import 'dart:math';

import 'package:edhtools/logic/league.dart';
import 'package:edhtools/logic/swiss.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, PlayerData> makePlayers(int n) => {
      for (var i = 0; i < n; i++)
        'p$i': PlayerData(id: 'p$i', nick: 'Jugador $i', joinedAt: i)
    };

void main() {
  const pts = Points(win: 5, draw: 1, loss: 0, bye: 5);

  group('CSV de logros', () {
    test('lee encabezado, coma y tipos en español', () {
      const csv = 'Nombre,Descripcion,Tipo,Puntos\n'
          'Primera sangre,Hacer el primer daño,Una vez por ronda,1\n'
          '"Comandante, al fin",Lanzar tu comandante,Una vez por jugador,1\n'
          'Asistencia,Llegar a tiempo,Automático,1\n'
          // Una quinta columna (formato antiguo con bono) se ignora.
          'Rendirse,Conceder la partida,Sin límite,-2,1\n';
      final r = parseAchievementsCsv(csv);
      expect(r.errors, isEmpty);
      expect(r.items.length, 4);
      expect(r.items[0].type, AchType.round);
      expect(r.items[1].name, 'Comandante, al fin');
      expect(r.items[3].points, -2);
      expect(r.items[2].type, AchType.auto);
      expect(r.items[3].type, AchType.unlimited);
      expect(r.items.map((a) => a.id).toSet().length, 4);
    });

    test('punto y coma, decimales con coma y errores por fila', () {
      const csv = 'Robo;Robar un permanente;una vez por jugador;0,5;0\n'
          ';sin nombre;auto;1;0\n'
          'Raro;tipo raro;mensual;1;0\n';
      final r = parseAchievementsCsv(csv);
      expect(r.items.length, 1);
      expect(r.items.first.points, 0.5);
      expect(r.errors.length, 2);
    });

    test('ids seguros y únicos', () {
      expect(achIdFromName('¡Ñandú Rápido!', {}), 'nandurapido');
      expect(achIdFromName('combo', {'combo'}), 'combo2');
    });
  });

  group('puntaje de liga', () {
    final achs = {
      'a': const Achievement(id: 'a', name: 'A', points: 1),
      'neg': const Achievement(id: 'neg', name: 'Neg', points: -2),
      'b': const Achievement(id: 'b', name: 'B', points: 3),
    };
    RoundData ronda(int n, Map<String, String> res) => RoundData(
          n: n,
          confirmed: true,
          tables: [
            TableData(t: 1, seats: ['p0', 'p1', 'p2', 'p3'], res: res),
          ],
        );

    test('resultado de mesa + logros', () {
      final r = ronda(1, {'p0': 'W', 'p1': 'L', 'p2': 'L', 'p3': 'L'});
      final claims = [
        const Claim(id: '1', round: 1, pid: 'p0', ach: 'a'),
        const Claim(id: '2', round: 1, pid: 'p1', ach: 'a'),
        const Claim(id: '3', round: 1, pid: 'p1', ach: 'b'),
      ];
      final s = leagueRoundScores(r, pts, achs, claims);
      expect(s['p0'], 5 + 1);
      expect(s['p1'], 0 + 1 + 3);
      expect(s['p2'], 0);
    });

    test('logros negativos restan puntos', () {
      final r = ronda(1, {'p0': 'W', 'p1': 'L', 'p2': 'L', 'p3': 'L'});
      final claims = [
        const Claim(id: '1', round: 1, pid: 'p0', ach: 'neg'),
        const Claim(id: '2', round: 1, pid: 'p1', ach: 'neg'),
      ];
      final s = leagueRoundScores(r, pts, achs, claims);
      expect(s['p0'], 5 - 2);
      expect(s['p1'], -2, reason: 'el puntaje de ronda puede quedar negativo');
      final st = computeLeagueStandings(
          rounds: [r], players: makePlayers(4), pts: pts,
          achievements: achs, claims: claims);
      expect(st.last.id, 'p1');
      expect(st.last.total, -2);
    });

    test('quien no jugó no ocupa puestos aunque otros tengan negativo', () {
      final r = ronda(1, {'p0': 'W', 'p1': 'L', 'p2': 'L', 'p3': 'L'});
      final claims = [const Claim(id: '1', round: 1, pid: 'p1', ach: 'neg')];
      final st = computeLeagueStandings(
          rounds: [r], players: makePlayers(6), pts: pts,
          achievements: achs, claims: claims);
      final jugaron = st.where((s) => s.roundsPlayed > 0).toList();
      expect(jugaron.length, 4);
      expect(jugaron.map((s) => s.rank), [1, 2, 3, 4]);
      expect(st.firstWhere((s) => s.id == 'p1').rank, 4);
    });

    test('puntajes máximos: mejores N rondas', () {
      final ps = makePlayers(4);
      final rounds = [
        ronda(1, {'p0': 'W', 'p1': 'L', 'p2': 'L', 'p3': 'L'}),
        ronda(2, {'p1': 'W', 'p0': 'L', 'p2': 'L', 'p3': 'L'}),
        ronda(3, {'p0': 'W', 'p1': 'L', 'p2': 'L', 'p3': 'L'}),
      ];
      final all = computeLeagueStandings(rounds: rounds, players: ps, pts: pts);
      final p0 = all.firstWhere((s) => s.id == 'p0');
      expect(p0.total, 10);
      final best1 = computeLeagueStandings(
          rounds: rounds, players: ps, pts: pts, maxScores: 1);
      final q0 = best1.firstWhere((s) => s.id == 'p0');
      final q1 = best1.firstWhere((s) => s.id == 'p1');
      expect(q0.total, 5);
      expect(q0.allPoints, 10);
      expect(q1.total, 5);
    });

    test('desempate por logro configurable', () {
      final ps = makePlayers(4);
      final rounds = [
        ronda(1, {'p0': 'D', 'p1': 'D', 'p2': 'D', 'p3': 'D'}),
      ];
      // p2 y p3 empatan en puntos (incluido el logro 'b' de 3 pts),
      // pero p3 tiene más veces el logro 'a' (que vale 0 en este caso).
      final achs2 = {
        'a': const Achievement(id: 'a', name: 'A', points: 0),
        'b': const Achievement(id: 'b', name: 'B', points: 3),
      };
      final claims = [
        const Claim(id: '1', round: 1, pid: 'p3', ach: 'a'),
        const Claim(id: '2', round: 1, pid: 'p3', ach: 'a'),
      ];
      final st = computeLeagueStandings(
        rounds: rounds,
        players: ps,
        pts: pts,
        achievements: achs2,
        claims: claims,
        tiebreakers: const ['ach:a', 'omw'],
      );
      final i2 = st.indexWhere((s) => s.id == 'p2');
      final i3 = st.indexWhere((s) => s.id == 'p3');
      expect(i3 < i2, true);
      expect(st.firstWhere((s) => s.id == 'p3').achCounts['a'], 2);
    });
  });

  group('mesas de liga', () {
    test('con líderes: 3+ mesas en orden inverso', () {
      final ps = makePlayers(13);
      final order = ps.keys.toList(); // p0 es el líder 1
      final r = buildLeagueRound(
        n: 2,
        participants: order,
        mode: PairingMode.leaders,
        order: order,
        prevRounds: const [],
        players: ps,
        pts: pts,
        rng: Random(3),
      );
      expect(r.tables.map((t) => t.seats.length).toList(), [4, 3, 3, 3]);
      expect(r.tableOf('p0')!.t, 3);
      expect(r.tableOf('p1')!.t, 2);
      expect(r.tableOf('p2')!.t, 1);
      expect(r.seated.length, 13);
    });

    test('con líderes: 2 mesas, líderes 1 y 2 juntos', () {
      final ps = makePlayers(7);
      final order = ps.keys.toList();
      final r = buildLeagueRound(
        n: 1,
        participants: order,
        mode: PairingMode.leaders,
        order: order,
        prevRounds: const [],
        players: ps,
        pts: pts,
      );
      expect(r.tableOf('p0')!.t, 2);
      expect(r.tableOf('p1')!.t, 2);
      expect(r.tableOf('p2')!.t, 1);
    });

    test('aleatorio: solo los inscritos, mesas de 4 y 3', () {
      final ps = makePlayers(12);
      final part = ['p0', 'p2', 'p4', 'p6', 'p8', 'p10', 'p11'];
      final r = buildLeagueRound(
        n: 1,
        participants: part,
        mode: PairingMode.random,
        order: const [],
        prevRounds: const [],
        players: ps,
        pts: pts,
      );
      expect(r.seated, part.toSet());
      expect(r.tables.map((t) => t.seats.length).toList(), [4, 3]);
    });

    test('5 inscritos: mesa de 4 + bye', () {
      final ps = makePlayers(5);
      final r = buildLeagueRound(
        n: 1,
        participants: ps.keys.toList(),
        mode: PairingMode.leaders,
        order: ps.keys.toList(),
        prevRounds: const [],
        players: ps,
        pts: pts,
      );
      expect(r.tables.single.seats.length, 4);
      expect(r.byes.length, 1);
      expect(r.byes.first.startsWith('p0'), false, reason: 'el líder no recibe bye');
    });
  });

  test('ids de reclamo según el tipo', () {
    const a = Achievement(id: 'x', name: 'X', type: AchType.round);
    const b = Achievement(id: 'y', name: 'Y', type: AchType.player);
    const c = Achievement(id: 'z', name: 'Z', type: AchType.unlimited);
    expect(claimId(a, 3, 'u1'), 'r3-x');
    expect(claimId(b, 3, 'u1'), 'r3-y-u1');
    expect(claimId(c, 3, 'u1', suffix: 'abc'), 'r3-z-u1-abc');
  });
}
