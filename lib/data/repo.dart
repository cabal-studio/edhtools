import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../logic/swiss.dart';

class Tournament {
  final String code;
  final String name;
  final String organizerId;
  final int rounds;
  final int roundMinutes;
  final Points pts;
  final String status; // registration | round | review | finished
  final int currentRound;
  final int? timerEnds; // epoch ms
  final int? timerPaused; // ms restantes si está en pausa

  Tournament.fromMap(this.code, Map<String, dynamic> m)
      : name = (m['name'] as String?) ?? 'Torneo',
        organizerId = (m['organizerId'] as String?) ?? '',
        rounds = asInt(m['rounds'], 4),
        roundMinutes = asInt(m['roundMinutes'], 75),
        pts = Points.fromMap(Map<String, dynamic>.from(m['pts'] ?? const {})),
        status = (m['status'] as String?) ?? 'registration',
        currentRound = asInt(m['currentRound']),
        timerEnds = m['timerEnds'] is num ? asInt(m['timerEnds']) : null,
        timerPaused = m['timerPaused'] is num ? asInt(m['timerPaused']) : null;

  /// Milisegundos restantes (negativo = tiempo cumplido, turnos extra).
  int? remainingMs() {
    if (timerPaused != null) return timerPaused;
    if (timerEnds != null) {
      return timerEnds! - DateTime.now().millisecondsSinceEpoch;
    }
    return null;
  }
}

class Report {
  final String by;
  final int round, table;
  final Map<String, String> res;
  Report.fromMap(Map<String, dynamic> m)
      : by = (m['by'] as String?) ?? '',
        round = asInt(m['round']),
        table = asInt(m['table']),
        res = Map<String, String>.from(m['res'] ?? const {});
}

class MyTournamentRef {
  final String code, name;
  MyTournamentRef(this.code, this.name);
}

/// Acceso a Firestore. Estructura:
///  tournaments/{CODE}
///  tournaments/{CODE}/players/{pid}
///  tournaments/{CODE}/rounds/r{n}
///  tournaments/{CODE}/reports/r{n}-t{t}
///  users/{uid}  -> { organized: [{code,name}], joined: [{code,name}], nick }
class Repo {
  Repo._();
  static final Repo i = Repo._();

  final _db = FirebaseFirestore.instance;
  String get uid => FirebaseAuth.instance.currentUser!.uid;
  int get now => DateTime.now().millisecondsSinceEpoch;

  DocumentReference<Map<String, dynamic>> tDoc(String code) =>
      _db.doc('tournaments/$code');
  DocumentReference<Map<String, dynamic>> roundDoc(String code, int n) =>
      _db.doc('tournaments/$code/rounds/r$n');
  DocumentReference<Map<String, dynamic>> get meDoc => _db.doc('users/$uid');

  // ---------- lecturas en vivo ----------
  Stream<Tournament?> tournament(String code) => tDoc(code)
      .snapshots()
      .map((s) => s.exists ? Tournament.fromMap(code, s.data()!) : null);

  Stream<Map<String, PlayerData>> players(String code) => _db
      .collection('tournaments/$code/players')
      .snapshots()
      .map((q) => {
            for (final d in q.docs) d.id: PlayerData.fromMap(d.id, d.data())
          });

  Stream<Map<int, RoundData>> rounds(String code) =>
      _db.collection('tournaments/$code/rounds').snapshots().map((q) => {
            for (final d in q.docs)
              asInt(d.data()['n']): RoundData.fromMap(d.data())
          });

  Stream<Map<String, Report>> reports(String code) => _db
      .collection('tournaments/$code/reports')
      .snapshots()
      .map((q) => {for (final d in q.docs) d.id: Report.fromMap(d.data())});

  Stream<Map<String, dynamic>> me() =>
      meDoc.snapshots().map((s) => s.data() ?? const {});

  static List<MyTournamentRef> refs(Map<String, dynamic> me, String key) =>
      ((me[key] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .map((m) => MyTournamentRef('${m['code']}', '${m['name']}'))
          .toList()
          .reversed
          .toList();

  Future<void> _remember(String key, String code, String name) =>
      meDoc.set({
        key: FieldValue.arrayUnion([
          {'code': code, 'name': name}
        ])
      }, SetOptions(merge: true));

  // ---------- organizador ----------
  static const _alph = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  String _genCode() {
    final r = Random.secure();
    return List.generate(6, (_) => _alph[r.nextInt(_alph.length)]).join();
  }

  /// Crea el torneo con una clave única de 6 caracteres y la devuelve.
  Future<String> createTournament({
    required String name,
    required int rounds,
    required int roundMinutes,
    required Points pts,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = _genCode();
      final ref = tDoc(code);
      final created = await _db.runTransaction((tx) async {
        final s = await tx.get(ref);
        if (s.exists) return false;
        tx.set(ref, {
          'code': code,
          'name': name,
          'organizerId': uid,
          'rounds': rounds,
          'roundMinutes': roundMinutes,
          'pts': pts.toMap(),
          'status': 'registration',
          'currentRound': 0,
          'timerEnds': null,
          'timerPaused': null,
          'createdAt': now,
        });
        return true;
      });
      if (created) {
        await _remember('organized', code, name);
        return code;
      }
    }
    throw Exception('No se pudo generar una clave única');
  }

  Future<void> addManualPlayer(String code, String nick) =>
      _db.collection('tournaments/$code/players').add(
          {'nick': nick, 'uid': null, 'dropped': false, 'joinedAt': now});

  Future<void> removePlayer(String code, String pid) =>
      _db.doc('tournaments/$code/players/$pid').delete();

  Future<void> setDropped(String code, String pid, bool dropped) =>
      _db.doc('tournaments/$code/players/$pid').update({'dropped': dropped});

  Future<void> startTournament(Tournament t, Map<String, PlayerData> ps) async {
    final r = buildRound(1, const [], ps, t.pts);
    await roundDoc(t.code, 1).set(r.toMap());
    await tDoc(t.code).update({
      'status': 'round',
      'currentRound': 1,
      'timerEnds': now + t.roundMinutes * 60000,
      'timerPaused': null,
    });
  }

  Future<void> saveTables(String code, int n, List<TableData> tables) =>
      roundDoc(code, n)
          .update({'tables': tables.map((t) => t.toMap()).toList()});

  Future<void> setStatus(String code, String status) =>
      tDoc(code).update({'status': status});

  Future<void> togglePause(Tournament t) {
    if (t.timerPaused != null) {
      return tDoc(t.code)
          .update({'timerEnds': now + t.timerPaused!, 'timerPaused': null});
    }
    final rem = (t.timerEnds ?? now) - now;
    return tDoc(t.code).update({'timerPaused': rem, 'timerEnds': null});
  }

  Future<void> addMinutes(Tournament t, int min) {
    final ms = min * 60000;
    if (t.timerPaused != null) {
      return tDoc(t.code).update({'timerPaused': t.timerPaused! + ms});
    }
    return tDoc(t.code).update({'timerEnds': (t.timerEnds ?? now) + ms});
  }

  Future<void> resetTimer(Tournament t) => tDoc(t.code).update(
      {'timerEnds': now + t.roundMinutes * 60000, 'timerPaused': null});

  /// Confirma la ronda actual y lanza la siguiente (o finaliza).
  Future<void> confirmAndNext(Tournament t, Map<int, RoundData> rounds,
      Map<String, PlayerData> ps) async {
    final n = t.currentRound;
    await roundDoc(t.code, n).update({'confirmed': true});
    if (n >= t.rounds) {
      await tDoc(t.code).update(
          {'status': 'finished', 'timerEnds': null, 'timerPaused': null});
      return;
    }
    final prev = (rounds.values.where((r) => r.n <= n).toList()
          ..sort((a, b) => a.n.compareTo(b.n)))
        .map((r) => r.n == n ? r.withConfirmed(true) : r)
        .toList();
    final next = buildRound(n + 1, prev, ps, t.pts);
    await roundDoc(t.code, n + 1).set(next.toMap());
    await tDoc(t.code).update({
      'status': 'round',
      'currentRound': n + 1,
      'timerEnds': now + t.roundMinutes * 60000,
      'timerPaused': null,
    });
  }

  Future<void> saveSettings(String code, int rounds, int minutes, Points p) =>
      tDoc(code).update(
          {'rounds': rounds, 'roundMinutes': minutes, 'pts': p.toMap()});

  // ---------- jugador ----------
  /// Devuelve null si todo bien, o un mensaje para mostrar.
  Future<String?> join(String code, String nick) async {
    final s = await tDoc(code).get();
    if (!s.exists) return 'No existe un torneo con esa clave';
    final t = Tournament.fromMap(code, s.data()!);
    await meDoc.set({'nick': nick}, SetOptions(merge: true));
    await _remember('joined', code, t.name);
    final pRef = _db.doc('tournaments/$code/players/$uid');
    final p = await pRef.get();
    if (p.exists) {
      await pRef.update({'nick': nick, 'dropped': false});
      return null;
    }
    if (t.status == 'finished') return 'El torneo terminó: entras como espectador';
    await pRef.set(
        {'nick': nick, 'uid': uid, 'dropped': false, 'joinedAt': now});
    return t.status == 'registration'
        ? null
        : 'Torneo en curso: entrarás desde la próxima ronda';
  }

  Future<String?> watch(String code) async {
    final s = await tDoc(code).get();
    if (!s.exists) return 'No existe un torneo con esa clave';
    await _remember('joined', code, '${s.data()!['name']}');
    return null;
  }

  Future<void> sendReport(
          String code, int round, int table, Map<String, String> res) =>
      _db.doc('tournaments/$code/reports/r$round-t$table').set({
        'by': uid,
        'round': round,
        'table': table,
        'res': res,
        'at': now,
      });
}
