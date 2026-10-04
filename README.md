# Pixel Car Player

Pantalla de música para el carro + transmisor desde el celular. Un solo APK, dos modos.

La tableta del carro (head unit chino "máquina universal" K24) recibe el audio del celular por
Bluetooth A2DP, pero muestra muy poco: sin carátula, sin letras. **Pixel Car Player** resuelve eso:
el **celular** lee lo que suena en Spotify (título, artista, álbum, carátula, posición), busca la
letra sincronizada en [LRCLIB](https://lrclib.net) y lo **transmite** a la tableta por un canal de
datos aparte. La tableta solo muestra (estilo [Harmonix](https://github.com/SantiagortegaDev/harmonix)) y controla.

## Cómo funciona

```
 ┌──────────── Celular (modo "Transmisor") ─────────────┐        ┌──────── Tableta (modo "Pantalla") ───────┐
 │ Spotify ─► MediaSession                              │        │                                          │
 │   └─► TransmitterService (Kotlin, foreground)        │  TCP   │ LinkClient (Dart)                        │
 │        • lee título/artista/álbum/carátula/posición  │ ─────► │   • descubre por beacon UDP / gateway /   │
 │        • busca letras sincronizadas en LRCLIB        │  JSON  │     IP manual, o RFCOMM (BT)              │
 │        • servidor TCP :47321 + beacon UDP :47322     │ ◄───── │ CarController ─► CarPlayerScreen         │
 │        • servidor RFCOMM (BT clásico)                │  cmds  │   (pantalla completa estilo Harmonix:    │
 │        • ejecuta play/pause/next/prev/seek           │        │    portada, letras sync, wavy slider)    │
 │ Flutter UI: estado, permisos, autos conectados       │        │ Fallback: MediaSession local del radio   │
 └──────────────────────────────────────────────────────┘        └──────────────────────────────────────────┘
```

- El transmisor del celular es **nativo (Kotlin)** y corre como servicio en primer plano: sigue
  vivo con Spotify abierto y la pantalla apagada. La UI Flutter solo lo inicia/detiene y muestra su estado.
- Protocolo: una línea JSON por mensaje (ver [`docs/CONTRACT.md`](docs/CONTRACT.md)).
- El **audio** sigue yendo por Bluetooth como siempre; solo los **datos** usan Wi-Fi o Bluetooth RFCOMM.

## Capturas

| Tableta | Celular |
|---|---|
| ![Tableta](docs/screenshots/car_1280x720.png) | ![Celular](docs/screenshots/phone_main.png) |

Selección de modo: `docs/screenshots/setup_tablet.png`, `docs/screenshots/setup_phone.png`.
Más capturas de la tableta: `docs/screenshots/car_*.png`; del celular: `docs/screenshots/phone_*.png`.

## Instalación

1. Descarga el APK más reciente desde **Releases** (pre-release "beta") o desde los artefactos de GitHub Actions (ver "Qué APK instalar").
2. Instala la app en el celular y en la tableta (permite "orígenes desconocidos").
3. Al primer arranque elige el modo:
   - **Celular**: "Transmisor (celular con Spotify)".
   - **Tableta**: "Pantalla del carro (tableta)".
4. Puedes cambiarlo luego desde el menú (⋮ → "Cambiar modo").

## Qué APK instalar

Cada release trae cuatro APK, nombrados `pixel-car-player-<versión>-<versionCode>-<abi>.apk`:

| ABI | Cuándo usarlo |
|---|---|
| `arm64-v8a` | Celulares modernos y la mayoría de tabletas de 64 bits. Es el más liviano para ellos. |
| `armeabi-v7a` | Head units / radios Android viejos (32 bits). **Si el arm64 no instala en la tableta del carro, prueba este.** |
| `x86_64` | Emuladores y dispositivos x86. |
| `universal` | Funciona en cualquier dispositivo, pero pesa más. Si dudas, usa este. |

## Actualizar sin perder la configuración

Android solo actualiza una app encima de otra si **ambas están firmadas con la misma clave** y el
`versionCode` es mayor. Antes cada build del CI se firmaba con una clave debug nueva, así que no se podía
actualizar sin desinstalar (y se perdían los ajustes). Ahora:

- **Firma estable**: el repo incluye un keystore de release (`android/keystore/pixelcarplayer-release.jks`,
  contraseñas en `android/keystore/keystore.properties`). Todos los builds de release, locales o del CI, usan esa clave.
- **Versión creciente**: en CI `versionCode = GITHUB_RUN_NUMBER + 100` y `versionName = 1.<run>.0`;
  el release se etiqueta `v<versionName>`. Localmente se usa la versión de `pubspec.yaml`.
- Para actualizar: instala el APK nuevo **encima** del anterior, sin desinstalar. Se conservan datos y configuración.

> **Aviso de seguridad:** esta clave es **pública** (está commiteada en el repo) a propósito, por comodidad:
> es una app personal que se instala por sideload. Cualquiera podría firmar un APK que "actualice" la tuya.
> No uses esta clave para publicar en Play Store ni para una app con datos sensibles.

### Cambiar a una clave privada

1. Genera tu keystore: `keytool -genkeypair -v -keystore mi.jks -alias miclave -keyalg RSA -keysize 4096 -validity 10950`.
2. En GitHub → Settings → Secrets and variables → Actions, crea `ANDROID_KEYSTORE_BASE64` (`base64 -w0 mi.jks`),
   `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD` y `ANDROID_KEY_ALIAS`. El workflow genera `android/key.properties`
   con ellos, y ese archivo tiene prioridad sobre el keystore público. Para uso local, crea tú mismo `android/key.properties`
   (`storeFile` relativo a `android/app/`; está en `.gitignore`).
3. (Opcional) borra `android/keystore/` del repo.

> **Ojo:** cambiar de clave obliga a **desinstalar una vez** la app instalada (y se pierde su configuración),
> porque Android ve una firma distinta. Desde ahí, las actualizaciones vuelven a instalarse encima.
> La primera vez que pases de los builds viejos (clave debug) a esta clave también hace falta desinstalar una vez.

## Conexión

### Opción recomendada: Wi-Fi

1. Enciende el **hotspot** del celular y conecta la tableta a él (o conecten ambos a la misma red Wi-Fi).
2. En el celular abre la app, concede permisos y activa el transmisor.
3. Abre la app en la tableta: descubre al celular sola (beacon UDP, IP del gateway o IP manual).
   Si falla, escribe en la tableta la IP que el celular muestra en "Cómo conectar".
4. Mantén el audio Bluetooth emparejado como siempre.

### Opción alternativa: Bluetooth RFCOMM

Si el Android de la tableta expone el adaptador Bluetooth estándar: empareja celular y tableta,
y elige el celular en los ajustes de la tableta. No necesita Wi-Fi.

## Permisos (celular)

| Permiso | Para qué |
|---|---|
| Acceso a notificaciones | Obligatorio. Es lo que permite leer la sesión multimedia de Spotify. |
| Dispositivos cercanos (Bluetooth) | Servidor RFCOMM para el enlace sin Wi-Fi. |
| Notificaciones | Mostrar el aviso del servicio en primer plano. |

## Solución de problemas

- **La tableta no encuentra al celular**: verifica que estén en la misma red (o usa el hotspot del celular)
  y escribe la IP manualmente.
- **No aparece la canción**: Spotify debe estar **reproduciendo**; revisa que "Acceso a notificaciones" esté
  activo y que el origen elegido sea Spotify (o "Cualquier app").
- **El transmisor se detiene solo**: en el celular **desactiva la optimización de batería** para Pixel Car Player
  (Ajustes → Apps → Pixel Car Player → Batería → Sin restricciones).
- **Head unit "máquina universal" K24**: su módulo Bluetooth (XR829) es propietario y las apps de terceros
  no leen AVRCP de forma fiable. Si el Bluetooth de la tableta no sirve para el enlace de datos, **usa Wi-Fi**.
- Sin letras: no todas las canciones están en LRCLIB; la pantalla muestra "Sin letras".

## Compilar

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release                      # universal
flutter build apk --release --split-per-abi      # arm64-v8a, armeabi-v7a, x86_64
```

El release local se firma con `android/key.properties` si existe; si no, con `android/keystore/keystore.properties`;
si tampoco, con la clave debug. Los builds debug siempre usan la clave debug.

Vista previa web (para capturas): `flutter build web --release` y abre `?mode=phone` o `?mode=car&demo=1`.

GitHub Actions (`.github/workflows/build-release.yml`) corre análisis y tests en cada push a `main` y `claude/**`,
compila los APK por ABI + universal (`pixel-car-player-<versionName>-<versionCode>-<abi>.apk`) y los sube como artefactos.
Solo en `main` (o ejecución manual) crea además un pre-release `v<versionName>` marcado como "latest", con notas que
indican qué APK instalar y los últimos commits. Firma: ver "Actualizar sin perder la configuración"
(secretos opcionales `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`).

## Estructura

```
lib/
  main.dart            arranque y selección de modo
  core/                tema Harmonix, modelos, widgets compartidos
  data/bridge/         canal nativo tipado (pcp/native, pcp/events)
  data/link/           cliente del enlace (tableta)
  data/demo/           datos simulados
  car/                 UI de la tableta
  phone/               UI del celular (controlador + widgets)
  setup/               pantalla de selección de modo
android/               Kotlin: MediaSession, TransmitterService, RFCOMM
docs/                  PLAN.md, CONTRACT.md, screenshots/
```
