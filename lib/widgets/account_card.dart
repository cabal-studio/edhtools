import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/auth.dart';
import '../ui/theme.dart';

/// Indicador compacto para la barra superior: Google (verde) o Invitado.
class AccountChip extends StatelessWidget {
  const AccountChip({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, _) {
        final google = Auth.isGoogle;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            avatar: Icon(google ? Icons.verified_user : Icons.person_outline,
                size: 18, color: google ? kOk : kMuted),
            label: Text(
              google ? (Auth.email ?? 'Google') : 'Invitado',
              overflow: TextOverflow.ellipsis,
            ),
            side: BorderSide(color: google ? kOk.withValues(alpha: .6) : kLine),
            onPressed: () => showModalBottomSheet(
              context: context,
              showDragHandle: true,
              builder: (c) => const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: AccountCard(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tarjeta de cuenta: con qué cuenta entraste, cambiar de cuenta, entrar como
/// invitado o volver a entrar con la última cuenta usada.
class AccountCard extends StatefulWidget {
  const AccountCard({super.key});
  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  LastAccount? last;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    final l = await Auth.lastAccount();
    if (mounted) setState(() => last = l);
  }

  Future<void> _do(Future<void> Function() fn, String ok) async {
    setState(() => busy = true);
    try {
      await fn();
      if (mounted) toast(context, ok);
    } catch (e) {
      final msg = '$e';
      if (mounted && !msg.toLowerCase().contains('cancel')) {
        toast(context, 'No se pudo cambiar de cuenta: $msg');
      }
    }
    await _loadLast();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _guest() async {
    final ok = await confirmDialog(
      context,
      'Entrarás como invitado, sin cuenta.\n\n'
      'Mientras seas invitado no verás los torneos de ${Auth.email ?? 'tu cuenta'}. '
      'Podrás volver a entrar con esa cuenta con un toque.',
      ok: 'Entrar como invitado',
    );
    if (!ok || !mounted) return;
    await _do(Auth.continueAsGuest, 'Ahora estás como invitado');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, _) {
        final google = Auth.isGoogle;
        final l = last;
        final canReturn = !google && l != null;
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: google ? kOk.withValues(alpha: .6) : kLine),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor:
                      (google ? kOk : kMuted).withValues(alpha: .18),
                  child: Icon(google ? Icons.verified_user : Icons.person_outline,
                      color: google ? kOk : kMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        google
                            ? (Auth.displayName.isNotEmpty
                                ? Auth.displayName
                                : 'Cuenta de Google')
                            : 'Invitado (sin cuenta)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(
                        google
                            ? 'Conectado con Google · ${Auth.email ?? ''}'
                            : 'Tus torneos quedan solo en este dispositivo.',
                        style: TextStyle(
                            color: google ? kOk : kMuted, fontSize: 12.5)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              if (canReturn)
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _do(() => Auth.signInWithGoogle(hint: l.email),
                          'Entraste como ${l.email}'),
                  icon: const Icon(Icons.login),
                  label: Text('Volver a entrar como ${l.email}',
                      overflow: TextOverflow.ellipsis),
                ),
              if (canReturn) const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (google)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _do(Auth.signInWithGoogle, 'Cuenta cambiada'),
                    icon: const Icon(Icons.switch_account, size: 18),
                    label: const Text('Cambiar de cuenta'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _do(Auth.signInWithGoogle,
                            'Entraste con Google: tus torneos se sincronizan en web y otros teléfonos'),
                    icon: const Icon(Icons.login, size: 18),
                    label: Text(canReturn ? 'Usar otra cuenta de Google' : 'Entrar con Google'),
                  ),
                if (google)
                  OutlinedButton.icon(
                    onPressed: busy ? null : _guest,
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('Entrar como invitado'),
                  ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
