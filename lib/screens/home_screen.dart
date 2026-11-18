import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/auth.dart';
import '../ui/theme.dart';
import 'organize_screen.dart';
import 'play_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, _) => Scaffold(
        appBar: AppBar(actions: const [_AccountButton()]),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 12),
              const Icon(Icons.shield_moon_outlined, size: 72, color: kGold),
              const SizedBox(height: 8),
              Text('Edhtools',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: kGoldLight, fontWeight: FontWeight.w700)),
              const Text('Torneos EDH en mesas de 4 · suizo · desempates MTG',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMuted)),
              const SizedBox(height: 28),
              _BigButton(
                icon: Icons.sports_esports,
                title: 'Jugar torneo',
                subtitle: 'Entra con la clave del organizador',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PlayScreen())),
              ),
              const SizedBox(height: 14),
              _BigButton(
                icon: Icons.emoji_events_outlined,
                title: 'Organizar torneo',
                subtitle: 'Crea rondas, mesas y standings',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const OrganizeScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _BigButton(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: kGold.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: kGoldLight, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w700)),
                    Text(subtitle, style: const TextStyle(color: kMuted)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context) {
    final google = Auth.isGoogle;
    return PopupMenuButton<String>(
      icon: Icon(google ? Icons.account_circle : Icons.person_outline),
      itemBuilder: (_) => [
        PopupMenuItem(
            enabled: false,
            child: Text(google
                ? 'Conectado: ${Auth.email ?? 'Google'}'
                : 'Invitado (sin cuenta)')),
        if (!google)
          const PopupMenuItem(
              value: 'google', child: Text('Vincular cuenta de Google')),
        if (google)
          const PopupMenuItem(value: 'out', child: Text('Cerrar sesión')),
      ],
      onSelected: (v) => guard(context, () async {
        if (v == 'google') {
          await Auth.connectGoogle();
          if (context.mounted) {
            toast(context, 'Cuenta vinculada: úsala en web y otros teléfonos');
          }
        } else if (v == 'out') {
          await Auth.signOut();
        }
      }),
    );
  }
}
