# Edhtools

Torneos de Magic: The Gathering en formato **Commander / EDH**: rondas suizas en mesas
de 4 (las de 3 al final), reloj de ronda, revisión de puntos por el organizador,
standing en vivo con desempates MTG (Puntos, OMW%, MW%, OOMW%) y clave de acceso.

- **Web:** https://edhtools.web.app
- **Android:** paquete `com.cabalstudio.edhtools`
- **Backend:** Firebase (proyecto `edhtools`): Authentication (Google + Anónimo), Firestore

## Publicación automática
Cada cambio en `main` ejecuta `.github/workflows/publicar-web.yml`: revisa el código,
ejecuta las pruebas, compila la web y la publica en Firebase Hosting. Si algo falla,
no se publica y la versión anterior sigue en línea.

Requiere el secreto `FIREBASE_SERVICE_ACCOUNT_EDHTOOLS` en el repositorio
(se crea con `firebase init hosting:github`).

Las **reglas de Firestore** (`firestore.rules`) no se publican solas: tras cambiarlas,
ejecuta `publicar.ps1` en el PC o `firebase deploy --only firestore:rules`.

## Desarrollo local (Windows)
```powershell
flutter pub get
flutter test
flutter run -d chrome          # web
flutter run                    # Android (emulador o teléfono)
```

## Estructura
```
lib/logic/swiss.dart        emparejamiento suizo, mesas, puntos y desempates (sin Flutter)
lib/data/repo.dart          acceso a Firestore
lib/data/auth.dart          sesión anónima / Google
lib/screens/                pantallas (inicio, organizar, jugar, torneo)
firestore.rules             reglas de seguridad
```
