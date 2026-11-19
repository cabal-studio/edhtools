import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Última cuenta de Google usada en este dispositivo.
class LastAccount {
  final String email;
  final String name;
  const LastAccount(this.email, this.name);
  String get label => name.isNotEmpty ? '$name ($email)' : email;
}

/// Sesión sin pantalla de login:
///  * Al abrir la app se reutiliza la sesión guardada.
///  * En Android se intenta un inicio silencioso con la cuenta de Google del
///    teléfono. Si no hay, se entra como invitado (anónimo).
///  * Se puede entrar con Google, cambiar de cuenta o pasar a invitado en
///    cualquier momento. La última cuenta de Google queda recordada para
///    volver a entrar con un toque.
class Auth {
  static final _auth = FirebaseAuth.instance;
  static bool _gInit = false;
  static const _kEmail = 'last_google_email';
  static const _kName = 'last_google_name';

  static Future<void> _initGoogle() async {
    if (kIsWeb || _gInit) return;
    await GoogleSignIn.instance.initialize(serverClientId: kGoogleServerClientId);
    _gInit = true;
  }

  static Future<void> ensureSignedIn() async {
    if (_auth.currentUser != null) {
      await _rememberIfGoogle();
      return;
    }
    if (!kIsWeb) {
      try {
        await _initGoogle();
        final acc =
            await GoogleSignIn.instance.attemptLightweightAuthentication();
        if (acc != null) {
          final idToken = acc.authentication.idToken;
          if (idToken != null) {
            await _auth.signInWithCredential(
                GoogleAuthProvider.credential(idToken: idToken));
            await _rememberIfGoogle();
            return;
          }
        }
      } catch (e) {
        debugPrint('Inicio silencioso con Google no disponible: $e');
      }
    }
    await _auth.signInAnonymously();
  }

  static User? get user => _auth.currentUser;

  static bool get isGoogle =>
      _auth.currentUser?.providerData.any((p) => p.providerId == 'google.com') ??
      false;

  static bool get isGuest => !isGoogle;

  static String? get email => _auth.currentUser?.email ??
      _googleInfo()?.email;

  static String get displayName =>
      _auth.currentUser?.displayName ?? _googleInfo()?.displayName ?? '';

  static UserInfo? _googleInfo() {
    final ps = _auth.currentUser?.providerData ?? const <UserInfo>[];
    for (final p in ps) {
      if (p.providerId == 'google.com') return p;
    }
    return null;
  }

  // ---------- última cuenta ----------
  static Future<LastAccount?> lastAccount() async {
    try {
      final p = await SharedPreferences.getInstance();
      final e = p.getString(_kEmail);
      if (e == null || e.isEmpty) return null;
      return LastAccount(e, p.getString(_kName) ?? '');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _rememberIfGoogle() async {
    if (!isGoogle) return;
    final e = email;
    if (e == null || e.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kEmail, e);
      await p.setString(_kName, displayName);
    } catch (_) {}
  }

  static Future<void> forgetLastAccount() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kEmail);
      await p.remove(_kName);
    } catch (_) {}
  }

  // ---------- entrar / cambiar ----------
  /// Entra con Google.
  ///  * Si eres invitado, la sesión de invitado se vincula a la cuenta (se
  ///    conservan los torneos); si esa cuenta ya existía, se entra a ella.
  ///  * Si ya estás con Google, cambia a la cuenta que elijas.
  /// [hint]: correo sugerido (para "volver a entrar como…").
  static Future<void> signInWithGoogle({String? hint}) async {
    final current = _auth.currentUser;
    final switching = isGoogle;
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({
            'prompt': 'select_account',
            if (hint != null) 'login_hint': hint,
          });
        if (current != null && current.isAnonymous) {
          await current.linkWithPopup(provider);
        } else {
          await _auth.signInWithPopup(provider);
        }
      } else {
        await _initGoogle();
        if (switching) {
          // Para que aparezca el selector de cuentas.
          try {
            await GoogleSignIn.instance.signOut();
          } catch (_) {}
        }
        final acc = await GoogleSignIn.instance.authenticate();
        final cred =
            GoogleAuthProvider.credential(idToken: acc.authentication.idToken);
        if (current != null && current.isAnonymous) {
          await current.linkWithCredential(cred);
        } else {
          await _auth.signInWithCredential(cred);
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' && e.credential != null) {
        await _auth.signInWithCredential(e.credential!);
      } else {
        rethrow;
      }
    }
    await _auth.currentUser?.reload();
    await _rememberIfGoogle();
  }

  /// Compatibilidad con la versión anterior.
  static Future<void> connectGoogle() => signInWithGoogle();

  /// Sale de la cuenta de Google y entra como invitado (sin cuenta).
  /// La última cuenta queda recordada para volver a entrar.
  static Future<void> continueAsGuest() async {
    if (!kIsWeb && _gInit) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
    await _auth.signInAnonymously();
  }

  static Future<void> signOut() => continueAsGuest();
}
