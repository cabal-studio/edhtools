import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// Sin pantalla de login:
///  * Al abrir la app se reutiliza la sesión guardada.
///  * En Android se intenta un inicio silencioso con la cuenta de Google del
///    teléfono (Credential Manager). Si no hay, se entra como anónimo.
///  * El usuario puede "vincular" su cuenta de Google en un toque para usar
///    la misma identidad en web y en otros teléfonos.
class Auth {
  static final _auth = FirebaseAuth.instance;
  static bool _gInit = false;

  static Future<void> _initGoogle() async {
    if (kIsWeb || _gInit) return;
    await GoogleSignIn.instance.initialize(serverClientId: kGoogleServerClientId);
    _gInit = true;
  }

  static Future<void> ensureSignedIn() async {
    if (_auth.currentUser != null) return;
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
            return;
          }
        }
      } catch (e) {
        debugPrint('Inicio silencioso con Google no disponible: $e');
      }
    }
    await _auth.signInAnonymously();
  }

  static bool get isGoogle =>
      _auth.currentUser?.providerData.any((p) => p.providerId == 'google.com') ??
      false;

  static String? get email => _auth.currentUser?.email;

  /// Vincula la sesión anónima a Google (conserva los torneos).
  /// Si esa cuenta ya existía, cambia a ella.
  static Future<void> connectGoogle() async {
    final user = _auth.currentUser;
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        if (user != null && user.isAnonymous) {
          await user.linkWithPopup(provider);
        } else {
          await _auth.signInWithPopup(provider);
        }
        return;
      }
      await _initGoogle();
      final acc = await GoogleSignIn.instance.authenticate();
      final cred =
          GoogleAuthProvider.credential(idToken: acc.authentication.idToken);
      if (user != null && user.isAnonymous) {
        await user.linkWithCredential(cred);
      } else {
        await _auth.signInWithCredential(cred);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' && e.credential != null) {
        await _auth.signInWithCredential(e.credential!);
      } else {
        rethrow;
      }
    }
  }

  static Future<void> signOut() async {
    if (!kIsWeb && _gInit) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
    await _auth.signInAnonymously();
  }
}
