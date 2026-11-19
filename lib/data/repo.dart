import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../logic/swiss.dart';

/// Campo de inscripción configurable por torneo.
enum FieldMode { off, optional, required }

FieldMode fieldModeFrom(dynamic v) => switch (v) {
      'optional' => FieldMode.optional,
      'required' => FieldMode.required,
      _ => FieldMode.off,
    };

/// Cuándo ven todos los jugadores las barajas / votos (el organizador siempre).
enum ShareMode { never, always, end }

ShareMode shareModeFrom(dynamic v) => switch (v) {
      'always' => ShareMode.always,
      'end' => ShareMode.end,
      _ => ShareMode.never,
    };

class Tournament {
  final String code;
  final String name;
  final String organizerId;

  /// Dueño de los mantenedores (hoy el organizador; a futuro, una comunidad).
  final String ownerId;
  final int rounds;
  final int roundMinutes;
  final Points pts;

  /// registration → prep (mesas editables) → round (en juego y resultados)
  /// → prep de la siguiente … → finished
  final String status;
  final int currentRound;
  final int? timerEnds; // epoch ms
  final int? timerPaused; // ms restantes si está en pausa
  final FieldMode commanderField;
  final FieldMode deckListField;
  final ShareMode shareDecks;
  final ShareMode shareVotes;

  Tournament.fromMap(this.code, Map<String, dynamic> m)
      : name = (m['name'] as String?) ?? 'Torneo',
        organizerId = (m['organizerId'] as String?) ?? '',
        ownerId = (m['ownerId'] as String?) ?? (m['organizerId'] as String?) ?? '',
        rounds = asInt(m['rounds'], 4),
        roundMinutes = asInt(m['roundMinutes'], 75),
        pts = Points.fromMap(Map<String, dynamic>.from(m['pts'] ?? const {})),
        status = switch (m['status']) {
          'review' => 'round', // versión anterior
          final String s => s,
          _ => 'registration',
        },
        currentRound = asInt(m['currentRound']),
        timerEnds = m['timerEnds'] is num ? asInt(m['timerEnds']) : null,
        timerPaused = m['timerPaused'] is num ? asInt(m['timerPaused']) : null,
        commanderField = fieldModeFrom(m['commanderField']),
        deckListField = fieldModeFrom(m['deckListField']),
        shareDecks = shareModeFrom(m['shareDecks']),
        shareVotes = shareModeFrom(m['shareVotes']);

  bool get asksDeck =>
      commanderField != FieldMode.off || deckListField != FieldMode.off;

  bool canSee(ShareMode m, bool isOrg) =>
      isOrg ||
      m == ShareMode.always ||
      (m == ShareMode.end && status == 'finished');

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

class DeckInfo {
  final String commander;
  final String listUrl;
  const DeckInfo({this.commander = '', this.listUrl = ''});
  DeckInfo.fromMap(Map<String, dynamic> m)
      : commander = (m['commander'] as String?) ?? '',
        listUrl = (m['listUrl'] as String?) ?? '';
  bool get isEmpty => commander.isEmpty && listUrl.isEmpty;
}

class Vote {
  final String by;
  final int round;

  /// Índice de pregunta (como texto) → jugador votado, o null si lo dejó vacío.
  final Map<String, String?> picks;
  Vote.fromMap(Map<String, dynamic> m)
      : by = (m['by'] as String?) ?? '',
        round = asInt(m['round']),
        picks = Map<String, String?>.from(m['picks'] ?? const {});
}

class MyTournamentRef {
  final String code, name;

  /// Id del jugador dentro del torneo (null = el propio uid).
  final String? pid;
  MyTournamentRef(this.code, this.name, {this.pid});
}

/// Torneo en el que participó una persona del mantenedor.
class RosterTournament {
  final String code, name, pid;
  final int at;
  RosterTournament(this.code, this.name, this.pid, this.at);
  factory RosterTournament.fromMap(Map<String, dynamic> m) => RosterTournament(
      '${m['code']}', '${m['name']}', '${m['pid']}', asInt(m['at']));
  Map<String, dynamic> toMap() =>
      {'code': code, 'name': name, 'pid': pid, 'at': at};
}

/// Ficha de un jugador en el mantenedor del organizador (o comunidad).
///  * kind 'manual': lo agregó el organizador; id automático.
///  * kind 'app': tiene cuenta en la app; id = su uid.
class RosterPerson {
  final String id;
  final String nick;
  final String kind;
  final String? uid;
  final bool google;
  final List<RosterTournament> tournaments;
  final List<String> mergedFrom;
  RosterPerson.fromMap(this.id, Map<String, dynamic> m)
      : nick = (m['nick'] as String?) ?? '¿?',
        kind = (m['kind'] as String?) ?? 'manual',
        uid = m['uid'] as String?,
        google = m['google'] == true,
        tournaments = ((m['tournaments'] as List?) ?? const [])
            .map((e) => RosterTournament.fromMap(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at)),
        mergedFrom = List<String>.from(m['mergedFrom'] ?? const []);
  bool get isManual => kind == 'manual';

  /// Torneos distintos (un torneo puede aparecer dos veces tras una fusión).
  int get tournamentCount => tournaments.map((t) => t.code).toSet().length;
}

/// Acceso a Firestore. Estructura:
///  tournaments/{CODE}                         configuración y estado
///  tournaments/{CODE}/players/{pid}           nick, uid, drop
///  tournaments/{CODE}/decks/{pid}             comandante y lista (privado)
///  tournaments/{CODE}/rounds/r{n}             mesas, resultados, preguntas
///  tournaments/{CODE}/reports/r{n}-t{t}       resultado reportado por jugador
///  tournaments/{CODE}/votes/r{n}-{uid}        votos especiales (privado)
///  users/{uid}  -> { organized, joined, nick, voteQuestions }
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
  DocumentReference<Map<String, dynamic>> deckDoc(String code, String pid) =>
      _db.doc('tournaments/$code/decks/$pid');
  DocumentReference<Map<String, dynamic>> voteDoc(String code, int n) =>
      _db.doc('tournaments/$code/votes/r$n-$uid');
  DocumentReference<Map<String, dynamic>> get meDoc => _db.doc('users/$uid');

  /// Dueño de los mantenedores. Hoy es el propio organizador; a futuro podrá
  /// ser una comunidad de organizadores (rosters/{comunidad}).
  String get ownerId => uid;
  DocumentReference<Map<String, dynamic>> get ownerDoc =>
      _db.doc('rosters/$ownerId');
  CollectionReference<Map<String, dynamic>> get people =>
      _db.collection('rosters/$ownerId/people');

  // ---------- lecturas en vivo ----------
  Stream<Tournament?> tournament(String code) => tDoc(code)
      .snapshots()
      .map((s) => s.exists ? Tournament.fromMap(code, s.data()!) : null);

  Future<Tournament?> peek(String code) async {
    final s = await tDoc(code).get();
    return s.exists ? Tournament.fromMap(code, s.data()!) : null;
  }

  Stream<Map<String, PlayerData>> players(String code) => _db
      .collection('tournaments/$code/players')
      .snapshots()
      .map((q) => {
            for (final d in q.docs) d.id: PlayerData.fromMap(d.id, d.data())
          });

  Future<Map<String, PlayerData>> playersOnce(String code) async {
    final q = await _db.collection('tournaments/$code/players').get();
    return {for (final d in q.docs) d.id: PlayerData.fromMap(d.id, d.data())};
  }

  Stream<Map<int, RoundData>> rounds(String code) =>
      _db.collection('tournaments/$code/rounds').snapshots().map((q) => {
            for (final d in q.docs)
              asInt(d.data()['n']): RoundData.fromMap(d.data())
          });

  Future<List<RoundData>> roundsOnce(String code) async {
    final q = await _db.collection('tournaments/$code/rounds').get();
    return q.docs.map((d) => RoundData.fromMap(d.data())).toList()
      ..sort((a, b) => a.n.compareTo(b.n));
  }

  Stream<Map<String, Report>> reports(String code) => _db
      .collection('tournaments/$code/reports')
      .snapshots()
      .map((q) => {for (final d in q.docs) d.id: Report.fromMap(d.data())});

  /// Todas las barajas: solo si el organizador o la visibilidad lo permite.
  Stream<Map<String, DeckInfo>> decks(String code) => _db
      .collection('tournaments/$code/decks')
      .snapshots()
      .map((q) => {for (final d in q.docs) d.id: DeckInfo.fromMap(d.data())});

  Stream<DeckInfo?> myDeck(String code, String pid) => deckDoc(code, pid)
      .snapshots()
      .map((s) => s.exists ? DeckInfo.fromMap(s.data()!) : null);

  /// Todos los votos: solo si el organizador o la visibilidad lo permite.
  Stream<List<Vote>> votes(String code) => _db
      .collection('tournaments/$code/votes')
      .snapshots()
      .map((q) => q.docs.map((d) => Vote.fromMap(d.data())).toList());

  Stream<Vote?> myVote(String code, int n) => voteDoc(code, n)
      .snapshots()
      .map((s) => s.exists ? Vote.fromMap(s.data()!) : null);

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

  // ---------- organizador: torneo ----------
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
    FieldMode commanderField = FieldMode.off,
    FieldMode deckListField = FieldMode.off,
    ShareMode shareDecks = ShareMode.end,
    ShareMode shareVotes = ShareMode.never,
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
          'ownerId': uid,
          'rounds': rounds,
          'roundMinutes': roundMinutes,
          'pts': pts.toMap(),
          'status': 'registration',
          'currentRound': 0,
          'timerEnds': null,
          'timerPaused': null,
          'commanderField': commanderField.name,
          'deckListField': deckListField.name,
          'shareDecks': shareDecks.name,
          'shareVotes': shareVotes.name,
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

  Future<void> saveSettings(
    Tournament t, {
    required int rounds,
    required int minutes,
    required Points pts,
    required FieldMode commanderField,
    required FieldMode deckListField,
    required ShareMode shareDecks,
    required ShareMode shareVotes,
  }) =>
      tDoc(t.code).update({
        'rounds': rounds,
        'roundMinutes': minutes,
        'pts': pts.toMap(),
        'commanderField': commanderField.name,
        'deckListField': deckListField.name,
        'shareDecks': shareDecks.name,
        'shareVotes': shareVotes.name,
      });

  // ---------- organizador: jugadores ----------
  Future<void> addManualPlayer(String code, String nick,
      {DeckInfo deck = const DeckInfo()}) async {
    final ref = await _db.collection('tournaments/$code/players').add(
        {'nick': nick, 'uid': null, 'dropped': false, 'joinedAt': now});
    if (!deck.isEmpty) await saveDeck(code, ref.id, deck);
  }

  Future<void> removePlayer(String code, String pid) async {
    await _db.doc('tournaments/$code/players/$pid').delete();
    await deckDoc(code, pid).delete();
  }

  Future<void> renamePlayer(String code, String pid, String nick) =>
      _db.doc('tournaments/$code/players/$pid').update({'nick': nick});

  Future<void> setDropped(String code, String pid, bool dropped) =>
      _db.doc('tournaments/$code/players/$pid').update({'dropped': dropped});

  Future<void> saveDeck(String code, String pid, DeckInfo d) =>
      deckDoc(code, pid).set({
        'commander': d.commander.trim(),
        'listUrl': d.listUrl.trim(),
        'at': now,
      });

  // ---------- organizador: flujo de rondas ----------
  List<RoundData> _confirmedBefore(Map<int, RoundData> rounds, int n) =>
      (rounds.values.where((r) => r.n < n && r.confirmed).toList()
        ..sort((a, b) => a.n.compareTo(b.n)));

  /// Inscripción → preparación de la ronda 1 (mesas editables, sin reloj).
  Future<void> prepareFirstRound(Tournament t, Map<String, PlayerData> ps) async {
    final r = buildRound(1, const [], ps, t.pts);
    await roundDoc(t.code, 1).set(r.toMap());
    await tDoc(t.code).update({
      'status': 'prep',
      'currentRound': 1,
      'timerEnds': null,
      'timerPaused': null,
    });
  }

  /// Rehace el emparejamiento de la ronda en preparación (p. ej. tras
  /// agregar o quitar jugadores).
  Future<void> rebuildRound(Tournament t, Map<int, RoundData> rounds,
      Map<String, PlayerData> ps) async {
    final n = t.currentRound;
    final prev = _confirmedBefore(rounds, n);
    final keepQ = rounds[n]?.voteQuestions ?? const <String>[];
    final r = buildRound(n, prev, ps, t.pts).copyWith(voteQuestions: keepQ);
    await roundDoc(t.code, n).set(r.toMap());
  }

  /// Guarda mesas editadas a mano (recalcula repeticiones y asientos).
  Future<void> saveRoundTables(Tournament t, Map<int, RoundData> rounds,
      RoundData r, List<TableData> tables, List<String> byes) {
    final rep = countRepeats(_confirmedBefore(rounds, r.n), tables);
    return roundDoc(t.code, r.n).update({
      'tables': tables.map((x) => x.toMap()).toList(),
      'byes': byes,
      'repeats': rep,
      'seatOf': seatOfTables(tables),
    });
  }

  /// Solo resultados (durante la ronda).
  Future<void> saveResults(String code, int n, List<TableData> tables) =>
      roundDoc(code, n)
          .update({'tables': tables.map((x) => x.toMap()).toList()});

  Future<void> setVoteQuestions(String code, int n, List<String> qs) async {
    await roundDoc(code, n).update({'voteQuestions': qs});
    if (qs.isNotEmpty) await saveVoteQuestions(qs);
  }

  /// Preguntas guardadas del dueño (incluye las de la versión anterior,
  /// que se guardaban en users/{uid}).
  Stream<List<String>> voteQuestions() {
    late StreamController<List<String>> ctrl;
    List<String> a = const [], b = const [];
    StreamSubscription? s1, s2;
    void emit() => ctrl.add({...a, ...b}.toList()..sort());
    ctrl = StreamController<List<String>>(
      onListen: () {
        s1 = ownerDoc.snapshots().listen((d) {
          a = List<String>.from(d.data()?['voteQuestions'] ?? const []);
          emit();
        }, onError: ctrl.addError);
        s2 = meDoc.snapshots().listen((d) {
          b = List<String>.from(d.data()?['voteQuestions'] ?? const []);
          emit();
        }, onError: ctrl.addError);
      },
      onCancel: () async {
        await s1?.cancel();
        await s2?.cancel();
      },
    );
    return ctrl.stream;
  }

  Future<void> saveVoteQuestions(List<String> qs) => ownerDoc.set({
        'ownerId': ownerId,
        'voteQuestions': FieldValue.arrayUnion(qs),
      }, SetOptions(merge: true));

  Future<void> forgetVoteQuestion(String q) async {
    await ownerDoc.set({
      'voteQuestions': FieldValue.arrayRemove([q])
    }, SetOptions(merge: true));
    await meDoc.set({
      'voteQuestions': FieldValue.arrayRemove([q])
    }, SetOptions(merge: true));
  }

  Future<void> renameVoteQuestion(String from, String to) async {
    await forgetVoteQuestion(from);
    await saveVoteQuestions([to]);
  }

  /// Preparación → ronda en juego (arranca el reloj).
  Future<void> startRound(Tournament t) => tDoc(t.code).update({
        'status': 'round',
        'timerEnds': now + t.roundMinutes * 60000,
        'timerPaused': null,
      });

  /// Envía los puntos de la ronda: la confirma y prepara la siguiente
  /// (o finaliza el torneo si era la última).
  Future<void> submitPoints(Tournament t, Map<int, RoundData> rounds,
      Map<String, PlayerData> ps) async {
    final n = t.currentRound;
    await roundDoc(t.code, n).update({'confirmed': true});
    if (n >= t.rounds) {
      await tDoc(t.code).update(
          {'status': 'finished', 'timerEnds': null, 'timerPaused': null});
      return;
    }
    final prev = [
      ..._confirmedBefore(rounds, n),
      rounds[n]!.withConfirmed(true),
    ];
    final next = buildRound(n + 1, prev, ps, t.pts);
    await roundDoc(t.code, n + 1).set(next.toMap());
    await tDoc(t.code).update({
      'status': 'prep',
      'currentRound': n + 1,
      'timerEnds': null,
      'timerPaused': null,
    });
  }

  Future<void> _deleteWhere(String code, String coll, int round) async {
    final q = await _db
        .collection('tournaments/$code/$coll')
        .where('round', isEqualTo: round)
        .get();
    final b = _db.batch();
    for (final d in q.docs) {
      b.delete(d.reference);
    }
    await b.commit();
  }

  /// Deshace el último paso del torneo:
  ///  * ronda en juego      → preparación de esa ronda (borra resultados)
  ///  * preparación ronda N → ingreso de puntajes de la ronda N-1
  ///  * preparación ronda 1 → inscripción
  ///  * finalizado          → ingreso de puntajes de la última ronda
  Future<void> goBack(Tournament t, Map<int, RoundData> rounds) async {
    final n = t.currentRound;
    switch (t.status) {
      case 'round':
        final r = rounds[n];
        if (r != null) {
          await roundDoc(t.code, n).update({
            'tables': r.tables
                .map((x) => TableData(t: x.t, seats: x.seats).toMap())
                .toList(),
          });
        }
        await _deleteWhere(t.code, 'reports', n);
        await _deleteWhere(t.code, 'votes', n);
        await tDoc(t.code).update(
            {'status': 'prep', 'timerEnds': null, 'timerPaused': null});
      case 'prep':
        await roundDoc(t.code, n).delete();
        if (n <= 1) {
          await tDoc(t.code).update({
            'status': 'registration',
            'currentRound': 0,
            'timerEnds': null,
            'timerPaused': null,
          });
        } else {
          await roundDoc(t.code, n - 1).update({'confirmed': false});
          await tDoc(t.code).update({
            'status': 'round',
            'currentRound': n - 1,
            'timerEnds': null,
            'timerPaused': null,
          });
        }
      case 'finished':
        await roundDoc(t.code, n).update({'confirmed': false});
        await tDoc(t.code).update({'status': 'round'});
      default:
        break;
    }
  }

  // ---------- reloj ----------
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

  // ---------- mantenedor de jugadores ----------
  Stream<List<RosterPerson>> rosterPeople() => people.snapshots().map((q) =>
      q.docs.map((d) => RosterPerson.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.nick.toLowerCase().compareTo(b.nick.toLowerCase())));

  Stream<RosterPerson?> rosterPerson(String id) => people
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? RosterPerson.fromMap(d.id, d.data()!) : null);

  /// Referencia estable (sin la hora actual) para que arrayUnion no duplique.
  Map<String, dynamic> _tRef(Tournament t, String pid, int at) =>
      RosterTournament(t.code, t.name, pid, at).toMap();

  /// Agrega un jugador al torneo desde el organizador:
  ///  * con [rosterId]: alguien que ya está en el mantenedor (se reutiliza)
  ///  * sin [rosterId]: jugador nuevo; se crea su ficha manual.
  Future<void> addPlayerFromRoster(Tournament t, String nick,
      {String? rosterId, DeckInfo deck = const DeckInfo()}) async {
    String? rid = rosterId;
    final ts = now;
    if (rid == null) {
      // Ficha nueva en el mantenedor (si las reglas aún no lo permiten, el
      // jugador se agrega igual y se registra después con syncRoster).
      try {
        final ref = people.doc();
        await ref.set({
          'nick': nick,
          'kind': 'manual',
          'uid': null,
          'google': false,
          'tournaments': [],
          'createdAt': ts,
        });
        rid = ref.id;
      } catch (_) {
        rid = null;
      }
    }
    final ref = await _db.collection('tournaments/${t.code}/players').add({
      'nick': nick,
      'uid': null,
      'rosterId': rid,
      'dropped': false,
      'joinedAt': ts,
    });
    if (!deck.isEmpty) await saveDeck(t.code, ref.id, deck);
    if (rid != null) {
      try {
        await people.doc(rid).set({
          'tournaments': FieldValue.arrayUnion([_tRef(t, ref.id, ts)]),
          'updatedAt': now,
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  final _synced = <String>{};

  /// Registra en el mantenedor a todos los jugadores del torneo (el
  /// organizador lo ejecuta al abrir su torneo). Los jugadores con app usan
  /// su uid como ficha; los manuales antiguos reciben una ficha nueva.
  Future<void> syncRoster(Tournament t, Map<String, PlayerData> ps) async {
    for (final p in ps.values) {
      final key = '${t.code}/${p.id}/${p.nick}/${p.google}';
      if (_synced.contains(key)) continue;
      _synced.add(key);
      try {
        if (p.uid != null) {
          await people.doc(p.uid).set({
            'nick': p.nick,
            'kind': 'app',
            'uid': p.uid,
            'google': p.google,
            'tournaments': FieldValue.arrayUnion([_tRef(t, p.id, p.joinedAt)]),
            'updatedAt': now,
          }, SetOptions(merge: true));
        } else if (p.rosterId == null) {
          final rid = people.doc().id;
          await people.doc(rid).set({
            'nick': p.nick,
            'kind': 'manual',
            'uid': null,
            'google': false,
            'tournaments': [_tRef(t, p.id, p.joinedAt)],
            'createdAt': now,
          });
          await _db
              .doc('tournaments/${t.code}/players/${p.id}')
              .update({'rosterId': rid});
        }
      } catch (_) {
        _synced.remove(key);
      }
    }
  }

  Future<void> renameRosterPerson(String id, String nick) =>
      people.doc(id).update({'nick': nick, 'updatedAt': now});

  /// Fusiona una ficha manual con la de una cuenta de la app (idealmente
  /// Google): sus torneos pasan a la cuenta, que podrá verlos en su
  /// historial, y la ficha manual se elimina.
  Future<void> mergeRosterPeople(RosterPerson manual, RosterPerson target) async {
    final targetUid = target.uid;
    if (!manual.isManual || targetUid == null) {
      throw Exception('Solo se puede fusionar una ficha manual con una cuenta de la app');
    }
    await people.doc(target.id).set({
      'tournaments':
          FieldValue.arrayUnion(manual.tournaments.map((x) => x.toMap()).toList()),
      'mergedFrom': FieldValue.arrayUnion([manual.id]),
      'updatedAt': now,
    }, SetOptions(merge: true));
    // Vincula los registros de los torneos a la cuenta.
    for (final x in manual.tournaments) {
      try {
        await _db
            .doc('tournaments/${x.code}/players/${x.pid}')
            .update({'uid': targetUid, 'rosterId': target.id});
      } catch (_) {
        // Torneo borrado o de otro organizador: se omite.
      }
    }
    await people.doc(manual.id).delete();
  }

  /// Torneos vinculados a mi cuenta en mantenedores de cualquier organizador
  /// (incluye aquellos en que jugué como jugador manual y luego me fusionaron).
  Future<List<MyTournamentRef>> linkedTournaments() async {
    final q = await _db
        .collectionGroup('people')
        .where('uid', isEqualTo: uid)
        .get();
    final out = <MyTournamentRef>[];
    for (final d in q.docs) {
      final p = RosterPerson.fromMap(d.id, d.data());
      for (final x in p.tournaments) {
        out.add(MyTournamentRef(x.code, x.name, pid: x.pid));
      }
    }
    return out;
  }

  // ---------- jugador ----------
  /// Inscribe al usuario actual (jugador u organizador). Devuelve null si
  /// todo bien, o un mensaje para mostrar.
  Future<String?> join(String code, String nick,
      {DeckInfo deck = const DeckInfo()}) async {
    final google = FirebaseAuth.instance.currentUser?.providerData
            .any((p) => p.providerId == 'google.com') ??
        false;
    final t = await peek(code);
    if (t == null) return 'No existe un torneo con esa clave';
    await meDoc.set({'nick': nick}, SetOptions(merge: true));
    await _remember('joined', code, t.name);
    final pRef = _db.doc('tournaments/$code/players/$uid');
    final p = await pRef.get();
    if (p.exists) {
      await pRef.update({'nick': nick, 'dropped': false, 'google': google});
      if (!deck.isEmpty) await saveDeck(code, uid, deck);
      return null;
    }
    if (t.status == 'finished') {
      return 'El torneo terminó: entras como espectador';
    }
    await pRef.set({
      'nick': nick,
      'uid': uid,
      'dropped': false,
      'joinedAt': now,
      'google': google,
    });
    if (!deck.isEmpty) await saveDeck(code, uid, deck);
    return switch (t.status) {
      'registration' => null,
      'prep' => 'Inscrito: el organizador te asignará una mesa',
      _ => 'Torneo en curso: entrarás desde la próxima ronda',
    };
  }

  Future<String?> watch(String code) async {
    final t = await peek(code);
    if (t == null) return 'No existe un torneo con esa clave';
    await _remember('joined', code, t.name);
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

  Future<void> sendVote(String code, int round, Map<String, String?> picks) =>
      voteDoc(code, round).set({
        'by': uid,
        'round': round,
        'picks': picks,
        'at': now,
      });
}
