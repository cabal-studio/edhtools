import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../logic/league.dart';
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

  // ---- Liga ----
  /// 'swiss' (torneo tradicional) o 'league'.
  final String type;
  final bool achievementsOn;

  /// Logros activos en esta liga (copia del catálogo al configurarla).
  final Map<String, Achievement> achievements;
  final List<String> achOrder;
  final List<String> tiebreakers;

  /// Cuántos puntajes de ronda cuentan (0 = todos).
  final int maxScores;
  final ShareMode shareAchievements;

  final int createdAt;

  /// Fecha de realización elegida por el organizador (epoch ms), o null.
  final int? date;

  /// Fecha a mostrar: la de realización o, si no hay, la de creación.
  int get eventDate => date ?? createdAt;

  /// Abierto o en curso (no finalizado).
  bool get isActive => status != 'finished';

  bool get isLeague => type == 'league';
  List<Achievement> get achievementList => [
        for (final id in achOrder)
          if (achievements[id] != null) achievements[id]!,
        for (final a in achievements.values)
          if (!achOrder.contains(a.id)) a,
      ];

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
        shareVotes = shareModeFrom(m['shareVotes']),
        type = (m['type'] as String?) ?? 'swiss',
        achievementsOn = m['achievementsOn'] == true,
        achievements = {
          for (final e in Map<String, dynamic>.from(m['achievements'] ?? const {})
              .entries)
            e.key: Achievement.fromMap(
                e.key, Map<String, dynamic>.from(e.value as Map))
        },
        achOrder = List<String>.from(m['achOrder'] ?? const []),
        tiebreakers =
            List<String>.from(m['tiebreakers'] ?? kDefaultTiebreakers),
        maxScores = asInt(m['maxScores']),
        shareAchievements = shareModeFrom(m['shareAchievements']),
        createdAt = asInt(m['createdAt']),
        date = m['date'] is num ? asInt(m['date']) : null,
        groupId = m['groupId'] as String?,
        groupName = m['groupName'] as String?;

  /// Grupo de organizadores con el que se creó (null = individual).
  final String? groupId;
  final String? groupName;

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

/// Grupo de organizadores: tiene mantenedores propios (rosters/g_{id}) e
/// historial de torneos. El dueño agrega o quita miembros.
class Group {
  final String id;
  final String name;
  final String ownerUid;
  final List<String> members;
  final Map<String, String> names;
  final List<MyTournamentRef> tournaments;
  final int createdAt;
  Group.fromMap(this.id, Map<String, dynamic> m)
      : name = (m['name'] as String?) ?? 'Grupo',
        ownerUid = (m['owner'] as String?) ?? '',
        members = List<String>.from(m['members'] ?? const []),
        names = Map<String, String>.from(m['names'] ?? const {}),
        tournaments = ((m['tournaments'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e))
            .map((x) => MyTournamentRef('${x['code']}', '${x['name']}'))
            .toList()
            .reversed
            .toList(),
        createdAt = asInt(m['createdAt']);

  /// Dueño de los mantenedores del grupo (rosters/{owner}).
  String get owner => 'g_$id';
  String nameOf(String uid) => names[uid] ?? 'Miembro';
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
  /// [owner] null = mis propios mantenedores; 'g_{id}' = los de un grupo.
  String get ownerId => uid;
  String _o(String? owner) => owner ?? uid;
  DocumentReference<Map<String, dynamic>> ownerDocOf(String? owner) =>
      _db.doc('rosters/${_o(owner)}');
  CollectionReference<Map<String, dynamic>> peopleOf(String? owner) =>
      _db.collection('rosters/${_o(owner)}/people');
  DocumentReference<Map<String, dynamic>> get ownerDoc => ownerDocOf(null);
  CollectionReference<Map<String, dynamic>> get people => peopleOf(null);

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
    int? date,
    Group? group,
    Map<String, dynamic> extra = const {},
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = _genCode();
      final ref = tDoc(code);
      final keyRef = _db.doc('roundKeys/$code');
      final created = await _db.runTransaction((tx) async {
        final s = await tx.get(ref);
        if (s.exists) return false;
        final k = await tx.get(keyRef);
        if (k.exists) return false;
        tx.set(ref, {
          'code': code,
          'name': name,
          'organizerId': uid,
          'ownerId': group?.owner ?? uid,
          'groupId': group?.id,
          'groupName': group?.name,
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
          'date': date ?? now,
          ...extra,
        });
        return true;
      });
      if (created) {
        await _remember('organized', code, name);
        if (group != null) {
          await groupDoc(group.id).update({
            'tournaments': FieldValue.arrayUnion([
              {'code': code, 'name': name}
            ])
          });
        }
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

  Future<void> setVoteQuestions(String code, int n, List<String> qs,
      {String? owner}) async {
    await roundDoc(code, n).update({'voteQuestions': qs});
    if (qs.isNotEmpty) await saveVoteQuestions(qs, owner: owner);
  }

  /// Preguntas guardadas del dueño (incluye las de la versión anterior,
  /// que se guardaban en users/{uid}).
  Stream<List<String>> voteQuestions({String? owner}) {
    final personal = _o(owner) == uid;
    late StreamController<List<String>> ctrl;
    List<String> a = const [], b = const [];
    StreamSubscription? s1, s2;
    void emit() => ctrl.add({...a, ...b}.toList()..sort());
    ctrl = StreamController<List<String>>(
      onListen: () {
        s1 = ownerDocOf(owner).snapshots().listen((d) {
          a = List<String>.from(d.data()?['voteQuestions'] ?? const []);
          emit();
        }, onError: ctrl.addError);
        if (!personal) return;
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

  Future<void> saveVoteQuestions(List<String> qs, {String? owner}) =>
      ownerDocOf(owner).set({
        'ownerId': _o(owner),
        'voteQuestions': FieldValue.arrayUnion(qs),
      }, SetOptions(merge: true));

  Future<void> forgetVoteQuestion(String q, {String? owner}) async {
    await ownerDocOf(owner).set({
      'voteQuestions': FieldValue.arrayRemove([q])
    }, SetOptions(merge: true));
    if (_o(owner) != uid) return;
    await meDoc.set({
      'voteQuestions': FieldValue.arrayRemove([q])
    }, SetOptions(merge: true));
  }

  Future<void> renameVoteQuestion(String from, String to, {String? owner}) async {
    await forgetVoteQuestion(from, owner: owner);
    await saveVoteQuestions([to], owner: owner);
  }

  /// Preparación → ronda en juego (arranca el reloj). En liga entrega los
  /// logros automáticos.
  Future<void> startRound(Tournament t, {RoundData? round}) async {
    if (t.isLeague && round != null) await _grantAutoAchievements(t, round);
    await tDoc(t.code).update({
      'status': 'round',
      'timerEnds': now + t.roundMinutes * 60000,
      'timerPaused': null,
    });
  }

  /// Envía los puntos de la ronda: la confirma y prepara la siguiente
  /// (o finaliza el torneo si era la última).
  Future<void> submitPoints(Tournament t, Map<int, RoundData> rounds,
      Map<String, PlayerData> ps,
      {List<Claim> claims = const []}) async {
    final n = t.currentRound;
    await roundDoc(t.code, n).update({'confirmed': true});
    if (t.isLeague) {
      final r = rounds[n];
      if (r != null) await _storeLeagueRound(t, r, claims);
      await tDoc(t.code).update(
          {'status': 'between', 'timerEnds': null, 'timerPaused': null});
      return;
    }
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
    if (t.isLeague) return _goBackLeague(t, rounds);
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

  /// Volver atrás en liga:
  ///  * inscripción de ronda N → entre rondas (borra la ronda N y su clave)
  ///  * preparación           → inscripción de la misma ronda (borra mesas)
  ///  * ronda en juego        → preparación (borra resultados, reportes, votos y logros)
  ///  * entre rondas          → ingreso de puntajes de la última ronda
  ///  * finalizada            → entre rondas
  Future<void> _goBackLeague(Tournament t, Map<int, RoundData> rounds) async {
    final n = t.currentRound;
    final r = rounds[n];
    switch (t.status) {
      case 'registration':
        if (r?.key != null) await _db.doc('roundKeys/${r!.key}').delete();
        await _deleteWhere(t.code, 'entries', n);
        await roundDoc(t.code, n).delete();
        await tDoc(t.code).update({
          'status': 'between',
          'currentRound': n - 1,
          'timerEnds': null,
          'timerPaused': null,
        });
      case 'prep':
        await roundDoc(t.code, n).update(
            {'tables': [], 'byes': [], 'repeats': 0, 'seatOf': {}});
        await tDoc(t.code).update({'status': 'registration'});
      case 'round':
        if (r != null) {
          await roundDoc(t.code, n).update({
            'tables': r.tables
                .map((x) => TableData(t: x.t, seats: x.seats).toMap())
                .toList(),
          });
        }
        await _deleteWhere(t.code, 'reports', n);
        await _deleteWhere(t.code, 'votes', n);
        await _deleteWhere(t.code, 'claims', n);
        await tDoc(t.code).update(
            {'status': 'prep', 'timerEnds': null, 'timerPaused': null});
      case 'between':
        if (n < 1) return;
        await roundDoc(t.code, n).update({'confirmed': false});
        await tDoc(t.code).update(
            {'status': 'round', 'timerEnds': null, 'timerPaused': null});
      case 'finished':
        await tDoc(t.code).update({'status': 'between'});
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

  // ---------- liga ----------
  Future<String> createLeague({
    required String name,
    required int roundMinutes,
    required Points pts,
    required FieldMode commanderField,
    required FieldMode deckListField,
    required ShareMode shareDecks,
    required ShareMode shareVotes,
    required bool achievementsOn,
    required List<Achievement> achievements,
    required List<String> tiebreakers,
    required int maxScores,
    required ShareMode shareAchievements,
    int? date,
    Group? group,
  }) =>
      createTournament(
        date: date,
        group: group,
        name: name,
        rounds: 0,
        roundMinutes: roundMinutes,
        pts: pts,
        commanderField: commanderField,
        deckListField: deckListField,
        shareDecks: shareDecks,
        shareVotes: shareVotes,
        extra: {
          'type': 'league',
          'status': 'between',
          ..._leagueFields(achievementsOn, achievements, tiebreakers,
              maxScores, shareAchievements),
        },
      );

  Map<String, dynamic> _leagueFields(bool on, List<Achievement> achs,
          List<String> tiebreakers, int maxScores, ShareMode share) =>
      {
        'achievementsOn': on,
        'achievements': {for (final a in achs) a.id: a.toMap()},
        'achOrder': achs.map((a) => a.id).toList(),
        'tiebreakers': tiebreakers,
        'maxScores': maxScores,
        'shareAchievements': share.name,
      };

  Future<void> saveLeagueSettings(
    Tournament t, {
    required int minutes,
    required Points pts,
    required FieldMode commanderField,
    required FieldMode deckListField,
    required ShareMode shareDecks,
    required ShareMode shareVotes,
    required bool achievementsOn,
    required List<Achievement> achievements,
    required List<String> tiebreakers,
    required int maxScores,
    required ShareMode shareAchievements,
  }) =>
      tDoc(t.code).update({
        'roundMinutes': minutes,
        'pts': pts.toMap(),
        'commanderField': commanderField.name,
        'deckListField': deckListField.name,
        'shareDecks': shareDecks.name,
        'shareVotes': shareVotes.name,
        ..._leagueFields(achievementsOn, achievements, tiebreakers, maxScores,
            shareAchievements),
      });

  Future<void> setDate(String code, int ms) =>
      tDoc(code).update({'date': ms});

  /// Busca una clave: torneo/liga (6 caracteres) o clave de ronda de liga.
  Future<({String code, int? round})?> resolveKey(String key) async {
    final t = await tDoc(key).get();
    if (t.exists) return (code: key, round: null);
    final k = await _db.doc('roundKeys/$key').get();
    if (!k.exists) return null;
    return (code: '${k.data()!['code']}', round: asInt(k.data()!['n']));
  }

  Future<String> _uniqueKey() async {
    for (var i = 0; i < 8; i++) {
      final k = _genCode();
      final a = await tDoc(k).get();
      if (a.exists) continue;
      final b = await _db.doc('roundKeys/$k').get();
      if (!b.exists) return k;
    }
    throw Exception('No se pudo generar una clave única');
  }

  /// Entre rondas → abre la inscripción de la ronda siguiente con su clave.
  Future<String> openLeagueRound(Tournament t,
      {required PairingMode pairing, int? date}) async {
    final n = t.currentRound + 1;
    final key = await _uniqueKey();
    await _db.doc('roundKeys/$key').set({'code': t.code, 'n': n, 'at': now});
    await roundDoc(t.code, n).set(RoundData(
      n: n,
      tables: const [],
      key: key,
      pairing: pairing.name,
      date: date,
    ).toMap());
    await tDoc(t.code).update({
      'status': 'registration',
      'currentRound': n,
      'timerEnds': null,
      'timerPaused': null,
    });
    return key;
  }

  Future<void> setRoundPairing(String code, int n, PairingMode m) =>
      roundDoc(code, n).update({'pairing': m.name});

  /// Inscritos de cada ronda de liga: ronda → jugadores.
  Stream<Map<int, Set<String>>> entries(String code) => _db
          .collection('tournaments/$code/entries')
          .snapshots()
          .map((q) {
        final out = <int, Set<String>>{};
        for (final d in q.docs) {
          out.putIfAbsent(asInt(d.data()['round']), () => {}).add(
              '${d.data()['pid']}');
        }
        return out;
      });

  Future<void> addEntry(String code, int n, String pid) =>
      _db.doc('tournaments/$code/entries/r$n-$pid').set(
          {'round': n, 'pid': pid, 'at': now, 'by': uid});

  Future<void> removeEntry(String code, int n, String pid) =>
      _db.doc('tournaments/$code/entries/r$n-$pid').delete();

  List<String> _leagueOrder(Tournament t, Map<int, RoundData> rounds,
      Map<String, PlayerData> ps, List<Claim> claims) {
    final conf = rounds.values.where((r) => r.confirmed).toList()
      ..sort((a, b) => a.n.compareTo(b.n));
    return computeLeagueStandings(
      rounds: conf,
      players: ps,
      pts: t.pts,
      achievements: t.achievementsOn ? t.achievements : const {},
      claims: claims,
      tiebreakers: t.tiebreakers,
      maxScores: t.maxScores,
    ).map((s) => s.id).toList();
  }

  /// Inscripción de la ronda → preparación (arma las mesas según el modo).
  Future<void> buildLeagueTables(Tournament t, Map<int, RoundData> rounds,
      Map<String, PlayerData> ps, Set<String> entered, List<Claim> claims) async {
    final n = t.currentRound;
    final cur = rounds[n];
    final mode = pairingFrom(cur?.pairing);
    final prev = rounds.values.where((r) => r.n < n && r.confirmed).toList()
      ..sort((a, b) => a.n.compareTo(b.n));
    final participants = entered
        .where((p) => ps.containsKey(p) && !(ps[p]!.dropped))
        .toList();
    final r = buildLeagueRound(
      n: n,
      participants: participants,
      mode: mode,
      order: _leagueOrder(t, rounds, ps, claims),
      prevRounds: prev,
      players: ps,
      pts: t.pts,
    );
    await roundDoc(t.code, n).update({
      'tables': r.tables.map((x) => x.toMap()).toList(),
      'byes': r.byes,
      'repeats': r.repeats,
      'seatOf': seatOfTables(r.tables),
    });
    if (t.status == 'registration') {
      await tDoc(t.code).update({'status': 'prep'});
    }
  }

  /// Reclamos de logros: todos (organizador o si se comparten) o los míos.
  Stream<List<Claim>> claims(String code) => _db
      .collection('tournaments/$code/claims')
      .snapshots()
      .map((q) => q.docs.map((d) => Claim.fromMap(d.id, d.data())).toList());

  Stream<List<Claim>> myClaims(String code, String pid) => _db
      .collection('tournaments/$code/claims')
      .where('pid', isEqualTo: pid)
      .snapshots()
      .map((q) => q.docs.map((d) => Claim.fromMap(d.id, d.data())).toList());

  Future<void> claimAchievement(
          String code, Achievement a, int round, String pid) =>
      _db.doc('tournaments/$code/claims/${claimId(a, round, pid)}').set({
        'round': round,
        'pid': pid,
        'ach': a.id,
        'by': uid,
        'at': now,
      });

  Future<void> removeClaim(String code, String id) =>
      _db.doc('tournaments/$code/claims/$id').delete();

  /// Al empezar una ronda de liga: logros automáticos para todos.
  Future<void> _grantAutoAchievements(Tournament t, RoundData r) async {
    if (!t.achievementsOn) return;
    final autos =
        t.achievementList.where((a) => a.type == AchType.auto).toList();
    if (autos.isEmpty) return;
    final b = _db.batch();
    for (final pid in r.seated) {
      for (final a in autos) {
        b.set(_db.doc('tournaments/${t.code}/claims/${claimId(a, r.n, pid)}'), {
          'round': r.n,
          'pid': pid,
          'ach': a.id,
          'by': uid,
          'at': now,
          'auto': true,
        });
      }
    }
    await b.commit();
  }

  Future<void> _storeLeagueRound(
      Tournament t, RoundData r, List<Claim> claims) {
    final d = storedRoundData(r, t.pts,
        t.achievementsOn ? t.achievements : const {}, claims, t.tiebreakers);
    return roundDoc(t.code, r.n).update({'scores': d.scores, 'achTb': d.achTb});
  }

  /// Recalcula los puntajes guardados de todas las rondas confirmadas (tras
  /// cambiar puntos, logros o desempates de la liga).
  Future<void> recomputeLeagueScores(
      Tournament t, Map<int, RoundData> rounds, List<Claim> claims) async {
    for (final r in rounds.values.where((r) => r.confirmed)) {
      await _storeLeagueRound(t, r, claims);
    }
  }

  Future<void> finishLeague(Tournament t) => tDoc(t.code).update(
      {'status': 'finished', 'timerEnds': null, 'timerPaused': null});

  // ---------- catálogo de logros (mantenedor) ----------
  CollectionReference<Map<String, dynamic>> achCatalogOf(String? owner) =>
      _db.collection('rosters/${_o(owner)}/achievements');

  Stream<List<Achievement>> achievementCatalog({String? owner}) =>
      achCatalogOf(owner).snapshots().map(
      (q) => q.docs.map((d) => Achievement.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Future<void> saveAchievement(Achievement a, {String? owner}) =>
      achCatalogOf(owner).doc(a.id).set({...a.toMap(), 'updatedAt': now});

  Future<void> deleteAchievement(String id, {String? owner}) =>
      achCatalogOf(owner).doc(id).delete();

  Future<void> importAchievements(List<Achievement> list, {String? owner}) async {
    final b = _db.batch();
    for (final a in list) {
      b.set(achCatalogOf(owner).doc(a.id), {...a.toMap(), 'updatedAt': now});
    }
    await b.commit();
  }

  // ---------- mantenedor de jugadores ----------
  Stream<List<RosterPerson>> rosterPeople({String? owner}) =>
      peopleOf(owner).snapshots().map((q) =>
      q.docs.map((d) => RosterPerson.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.nick.toLowerCase().compareTo(b.nick.toLowerCase())));

  Stream<RosterPerson?> rosterPerson(String id, {String? owner}) =>
      peopleOf(owner)
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? RosterPerson.fromMap(d.id, d.data()!) : null);

  /// Referencia estable (sin la hora actual) para que arrayUnion no duplique.
  Map<String, dynamic> _tRef(Tournament t, String pid, int at) =>
      RosterTournament(t.code, t.name, pid, at).toMap();

  /// Agrega un jugador al torneo desde el organizador:
  ///  * con [rosterId]: alguien que ya está en el mantenedor (se reutiliza)
  ///  * sin [rosterId]: jugador nuevo; se crea su ficha manual.
  Future<String> addPlayerFromRoster(Tournament t, String nick,
      {String? rosterId, DeckInfo deck = const DeckInfo()}) async {
    final people = peopleOf(t.ownerId);
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
    return ref.id;
  }

  final _synced = <String>{};

  /// Registra en el mantenedor a todos los jugadores del torneo (el
  /// organizador lo ejecuta al abrir su torneo). Los jugadores con app usan
  /// su uid como ficha; los manuales antiguos reciben una ficha nueva.
  Future<void> syncRoster(Tournament t, Map<String, PlayerData> ps) async {
    final people = peopleOf(t.ownerId);
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

  Future<void> renameRosterPerson(String id, String nick, {String? owner}) =>
      peopleOf(owner).doc(id).update({'nick': nick, 'updatedAt': now});

  /// Fusiona una ficha manual con la de una cuenta de la app (idealmente
  /// Google): sus torneos pasan a la cuenta, que podrá verlos en su
  /// historial, y la ficha manual se elimina.
  Future<void> mergeRosterPeople(RosterPerson manual, RosterPerson target,
      {String? owner}) async {
    final people = peopleOf(owner);
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
      {DeckInfo deck = const DeckInfo(), int? round}) async {
    final google = FirebaseAuth.instance.currentUser?.providerData
            .any((p) => p.providerId == 'google.com') ??
        false;
    final t = await peek(code);
    if (t == null) return 'No existe un torneo con esa clave';
    await meDoc.set({'nick': nick}, SetOptions(merge: true));
    await _remember('joined', code, t.name);
    final pRef = _db.doc('tournaments/$code/players/$uid');
    final p = await pRef.get();
    if (t.isLeague) {
      if (p.exists) {
        await pRef.update({'nick': nick, 'dropped': false, 'google': google});
      } else {
        await pRef.set({
          'nick': nick,
          'uid': uid,
          'dropped': false,
          'joinedAt': now,
          'google': google,
        });
      }
      if (!deck.isEmpty) await saveDeck(code, uid, deck);
      final open = t.status == 'registration' || t.status == 'prep';
      if (round != null && round != t.currentRound) {
        return 'Esa clave es de la ronda $round, que ya no está abierta. Quedaste inscrito en la liga.';
      }
      if (!open) {
        return 'Inscrito en la liga. Podrás entrar a la próxima ronda con su clave.';
      }
      await addEntry(code, t.currentRound, uid);
      return null;
    }
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

  // ---------- grupos de organizadores ----------
  DocumentReference<Map<String, dynamic>> groupDoc(String id) =>
      _db.doc('groups/$id');

  Stream<List<Group>> myGroups() => _db
      .collection('groups')
      .where('members', arrayContains: uid)
      .snapshots()
      .map((q) => q.docs.map((d) => Group.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Stream<Group?> group(String id) => groupDoc(id)
      .snapshots()
      .map((d) => d.exists ? Group.fromMap(d.id, d.data()!) : null);

  /// Crea el grupo (yo como dueño) y duplica mis mantenedores: jugadores,
  /// preguntas y logros. El historial del grupo parte vacío.
  Future<String> createGroup(String name, String myName) async {
    final ref = _db.collection('groups').doc();
    await ref.set({
      'name': name,
      'owner': uid,
      'members': [uid],
      'names': {uid: myName.isEmpty ? 'Dueño' : myName},
      'tournaments': [],
      'createdAt': now,
    });
    final dest = 'g_${ref.id}';
    final mine = await ownerDoc.get();
    final me = await meDoc.get();
    final qs = {
      ...List<String>.from(mine.data()?['voteQuestions'] ?? const []),
      ...List<String>.from(me.data()?['voteQuestions'] ?? const []),
    }.toList();
    await ownerDocOf(dest).set({
      'ownerId': dest,
      'groupId': ref.id,
      'voteQuestions': qs,
    });
    final ps = await people.get();
    final achs = await achCatalogOf(null).get();
    final writes = <(DocumentReference<Map<String, dynamic>>, Map<String, dynamic>)>[
      for (final d in ps.docs)
        (
          peopleOf(dest).doc(d.id),
          {
            ...d.data(),
            'tournaments': [],
            'mergedFrom': [],
            'copiedAt': now,
          }
        ),
      for (final d in achs.docs) (achCatalogOf(dest).doc(d.id), d.data()),
    ];
    for (var i = 0; i < writes.length; i += 400) {
      final b = _db.batch();
      for (final w in writes.skip(i).take(400)) {
        b.set(w.$1, w.$2);
      }
      await b.commit();
    }
    return ref.id;
  }

  Future<void> renameGroup(String id, String name) =>
      groupDoc(id).update({'name': name});

  /// Solo jugadores con cuenta de la app (uid) pueden ser miembros.
  Future<void> addGroupMember(String id, RosterPerson p) {
    final u = p.uid;
    if (u == null) {
      throw Exception('Solo se pueden agregar jugadores con cuenta (Google o app).');
    }
    return groupDoc(id).update({
      'members': FieldValue.arrayUnion([u]),
      'names.$u': p.nick,
    });
  }

  Future<void> removeGroupMember(String id, String memberUid) =>
      groupDoc(id).update({
        'members': FieldValue.arrayRemove([memberUid]),
        'names.$memberUid': FieldValue.delete(),
      });

  /// Un miembro (no dueño) se retira del grupo.
  Future<void> leaveGroup(String id) => groupDoc(id).update({
        'members': FieldValue.arrayRemove([uid]),
      });
}
