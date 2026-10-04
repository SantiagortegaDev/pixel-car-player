# Contratos entre componentes

Fuente de verdad para Dart ⇄ Kotlin y celular ⇄ tableta. Cambios aquí primero.

## 1. Protocolo de enlace (celular ⇄ tableta)

- Transporte: TCP puerto **47321** o RFCOMM (UUID `7c1e3a52-5b8e-4f0a-9d3c-2f6b8a4e91d7`, nombre `PixelCarPlayer`).
- Encoding: **una línea JSON UTF-8 por mensaje**, terminada en `\n`. Campo `t` = tipo.
- Mensajes desconocidos se ignoran. Versión de protocolo `v: 1`.

### Celular → tableta

| `t` | Campos | Cuándo |
|-----|--------|--------|
| `hello` | `v`, `device` (modelo del celular), `source` (paquete, ej. `com.spotify.music`) | al conectar |
| `track` | `id` (hash estable de título+artista+álbum+duración), `title`, `artist`, `album`, `durationMs`, `source` | cambio de canción y al conectar |
| `art` | `id` (id del track), `mime` (`image/jpeg`), `b64` (JPEG ≤ 640 px, calidad 85) | tras `track` si hay carátula |
| `state` | `playing` (bool), `positionMs`, `speed` (double) | cambio de estado, cada 5 s mientras suena, y al conectar |
| `lyrics` | `id`, `status` (`ok` \| `not_found` \| `loading`), `synced` (bool), `lines`: `[{ "ms": int, "text": str }]` | cuando se resuelven (LRCLIB) |
| `queue` | `items`: `[{ "title": str, "artist": str }]` — próximas canciones de la cola del reproductor (después del ítem activo si se conoce, si no toda la cola; máx 20; `[]` si no hay cola) | al conectar / `resync` (tras `lyrics`), al cambiar la cola y al cambiar de canción |
| `ping` | — | cada 10 s |

La tableta interpola la posición con su propio reloj desde el instante en que recibe `state`
(no se compara el reloj del celular).

### Tableta → celular

| `t` | Campos |
|-----|--------|
| `hello` | `v`, `device` |
| `cmd` | `action`: `play` \| `pause` \| `toggle` \| `next` \| `previous` \| `seek`; `positionMs` (solo `seek`) |
| `pong` | — (respuesta a `ping`) |
| `resync` | — (pide reenviar `track`, `art`, `state`, `lyrics`, `queue`) |

### Descubrimiento (Wi-Fi)

- El celular envía cada 2 s un **beacon UDP** al puerto **47322** (broadcast de cada interfaz IPv4
  activa + `255.255.255.255`): `{"t":"beacon","v":1,"device":"Pixel 8","port":47321,"id":"<id>"}`.
  Desde v2 también por un socket enlazado a cada red Wi-Fi (`Network.bindSocket`) hacia su broadcast
  (calculado del prefijo) y su gateway (unicast).
- La tableta intenta en paralelo: IP del beacon, IP del **gateway** Wi-Fi (caso hotspot del celular),
  IP manual guardada. Primera conexión TCP exitosa gana. Reintento con backoff (1 s → 10 s).
- Si no llega `ping` en 25 s → se considera caída y se reconecta.

### v2 — enlace bidireccional (ambos lados escuchan y ambos marcan)

Motivo: en Android 10+ un Wi-Fi sin internet (hotspot del carro) no es la red por defecto
del celular; los sockets sin enlazar salen por datos móviles y los beacons UDP del celular
no llegan. Por eso el celular también **marca al carro** con sockets enlazados a la red Wi-Fi
(`Network.bindSocket`), y el orden en que se abren las apps deja de importar.

- **Tableta**: además de marcar al celular, escucha TCP **47323** y emite cada 2 s un beacon UDP
  al puerto **47324**: `{"t":"car_beacon","v":2,"device":"<modelo>","id":"<id>","port":47323}`.
- **Celular**: además de su servidor 47321 y su beacon, marca al carro en: IP del **gateway** de
  cada red Wi-Fi (el carro cuando es hotspot), IPs de `car_beacon` recibidos (escucha 47324 en
  cada red Wi-Fi) e IP manual. Reintento con backoff 1→10 s y de inmediato ante cambios de red
  (`NetworkCallback`). Deja de marcar mientras tenga una pantalla conectada (cualquier sentido).
- El protocolo de líneas es el mismo sin importar quién inició la conexión: al conectar, el
  **celular** envía `hello`+snapshot; la **tableta** envía `hello`+`resync`.
- `hello` lleva `id` (identificador estable de instalación). La tableta mantiene **un solo**
  enlace: si llega otro con el mismo `id` del celular mientras hay uno activo y sano, cierra el
  nuevo; si el activo no respondió en 25 s, se queda con el nuevo. El celular hace lo mismo
  por `id` del carro (una conexión por carro).
  Implementación en el celular: "sano" = respondió `pong` (o mandó `hello`) hace ≤ 25 s; "nuevo" = el
  que se estableció (TCP) después. Si un cliente nunca respondió, gana el nuevo.
- Tableta → celular `{"t":"hotspot","ssid":str,"password":str}` tras `hello` (si el usuario lo
  permite, activado por defecto): el celular registra la red para unirse solo
  (`setHotspotAutoConnect`) y la guarda.

### v3 — emparejamiento seguro, más controles y cola con carátulas

**Autenticación (mutua, HMAC-SHA256).**
- `hello` agrega `nonce` (16 bytes hex, nuevo por conexión) y `id` (ya existía).
- Si un lado tiene `token` guardado para el `id` del otro, responde al `hello` con
  `{"t":"auth","mac":hex}` donde `mac = HMAC_SHA256(key = token (bytes de la cadena hex),
  msg = "<nonce del otro>:<id propio>")`, hex en minúsculas. El receptor verifica con su copia.
- La sesión queda **autenticada** cuando cada lado validó el `auth` del otro (o el lado tiene
  "Requerir emparejamiento" apagado: entonces confía sin validar, pero sigue respondiendo `auth`).
- Hasta autenticar: el **celular** solo envía `hello`/`auth`/`pair_*`/`ping` e ignora `cmd`;
  la **tableta** solo envía `hello`/`auth`/`pair_*`/`pong` (nada de `resync` ni `hotspot`).
  Al autenticar: el celular manda el snapshot; la tableta manda `resync` y `hotspot`.
- **Emparejar** (celular sin token para ese carro, o `auth` inválido):
  1. celular → `{"t":"pair_request","name":"<modelo>"}`; la tableta muestra un código de 6
     dígitos (válido 2 min) en pantalla grande y responde `{"t":"pair_shown"}`.
  2. El usuario escribe el código en el celular → `{"t":"pair","code":"123456","token":"<64 hex>"}`
     (token aleatorio de 32 bytes generado por el celular).
  3. La tableta valida → guarda `token` para ese `id` → `{"t":"pair_ok"}` (sesión autenticada).
     Si falla: `{"t":"pair_fail","reason":"code"|"expired"|"busy"}` (máx. 5 intentos por código).
- Prefs: celular `flutter.phone_require_pairing` (bool, def. true); tableta `car_require_pairing`
  (def. true). Tokens: celular en prefs nativas (`pcp_native`), tableta en prefs Dart
  (`car_trusted_phones`: JSON `{id: {token, name, pairedAt}}`).

**Controles y estado extra.**
- `cmd.action` agrega: `shuffle` (alternar), `repeat` (ciclo off→all→one), `like` (alternar
  "me gusta" vía acción personalizada de la app si existe), `skipToQueue` (+ `queueId`: int).
- `state` agrega: `shuffle` (bool|null), `repeat` ("off"|"all"|"one"|null), `liked` (bool|null),
  `canLike` (bool), `canShuffle` (bool), `canRepeat` (bool).
- `queue.items[]` agrega `id` (queueId, int) y `art` (JPEG 96 px base64, opcional; se envía como
  máximo para los primeros 12 elementos).

## 2. Canal nativo (Flutter ⇄ Kotlin)

`MethodChannel("pcp/native")` — en web/desktop no existe: el código Dart debe protegerse con
`kIsWeb` / try-catch `MissingPluginException`.

| Método | Args | Retorno | Lado |
|--------|------|---------|------|
| `getDeviceInfo` | — | `{model, manufacturer, sdkInt}` | ambos |
| `hasNotificationAccess` | — | `bool` | ambos |
| `openNotificationAccessSettings` | — | — | ambos |
| `requestRuntimePermissions` | — | `{bluetoothConnect: bool, postNotifications: bool}` | ambos |
| `setKeepScreenOn` | `{on: bool}` | — | tableta |
| `startTransmitter` | `{sourcePackage: String?}` (`null` = cualquier app de música; default Spotify) | `bool` | celular |
| `stopTransmitter` | — | — | celular |
| `getTransmitterStatus` | — | ver evento `transmitterStatus` | celular |
| `getGatewayIp` | — | `String?` | tableta |
| `getLocalIps` | — | `List<String>` | ambos |
| `acquireMulticastLock` / `releaseMulticastLock` | — | — | tableta |
| `getBondedDevices` | — | `[{name, address}]` | tableta |
| `connectRfcomm` | `{address}` | `bool` (conectó) | tableta |
| `sendRfcomm` | `{line: String}` (sin `\n`) | `bool` | tableta |
| `disconnectRfcomm` | — | — | tableta |
| `startLocalMediaWatch` | — | `bool` | tableta |
| `stopLocalMediaWatch` | — | — | tableta |
| `localMediaCommand` | `{action, positionMs?}` (mismas acciones que `cmd`) | `bool` | tableta |
| `canDrawOverlays` | — | `bool` (`true` bajo API 23) | tableta |
| `openOverlaySettings` | — | — (abre `ACTION_MANAGE_OVERLAY_PERMISSION`; fallback a info de la app) | tableta |
| `openBatteryOptimizationSettings` | — | — (abre `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`; fallback a info de la app) | tableta |
| `getHotspotState` | — | `{enabled: bool?, ssid: String?, password: String?, configuredSsid: String?, configuredPassword: String?, method, canWriteSettings: bool}` — `ssid`/`password` = red activa (la de LocalOnly si hay reserva, si no la configurada); `configuredSsid`/`configuredPassword` = hotspot configurado en Ajustes del equipo (getSoftApConfiguration → getWifiApConfiguration → `WifiConfigStoreSoftAp.xml` / `softap.conf` si son legibles; null si no). `enabled` null = no se pudo leer; `method`: `localOnly` (reserva propia activa) \| `tethering` \| `wifiAp` (lo encendimos nosotros) \| `system` (encendido por otro) \| `none` (apagado) \| `unknown`. ssid/password null si Android no deja leerlos | tableta |
| `setHotspotEnabled` | `{enabled: bool, allowLocalOnly: bool = false}` | `{ok, method: 'tethering'\|'wifiAp'\|'localOnly'\|'none', needsSettings: bool, ssid?, password?, error: String?}` — usa el hotspot **configurado en el equipo**: si ya está encendido (o encendiéndose) devuelve `ok:true` sin tocar nada; si no, tethering → `setWifiApEnabled`; confirma sondeando el estado ≤ 3 s. **Solo con `allowLocalOnly:true`** cae a LocalOnlyHotspot (red con SSID/clave aleatorios; pide ubicación / `NEARBY_WIFI_DEVICES`). `ok:true, method:'none'` = ya estaba como se pidió. `error` (código): `systemPathsFailed`, `permissionDenied`, `locationOff`, `noChannel`, `incompatibleMode`, `tetheringDisallowed`, `timeout`, `generic`, `unsupported` | tableta |
| `openHotspotSettings` | — | — (TetherSettings → `Settings$TetherSettingsActivity` → `Settings$WifiTetherSettingsActivity` → `android.settings.TETHER_SETTINGS` → Conexiones inalámbricas → Ajustes) | tableta |
| `openWriteSettings` | — | — (`ACTION_MANAGE_WRITE_SETTINGS` de esta app; habilita la vía tethering en Android 7–10) | tableta |
| `getNeighborIps` | — | `List<String>` IPv4 de `/proc/net/arp` (flags 0x2, MAC ≠ 0) + `ip neigh` (REACHABLE/STALE/DELAY/PROBE). Vacío si Android lo bloquea (10+ / 11+) | tableta |
| `requestAudioPermission` | — | `bool` (RECORD_AUDIO concedido, tras el diálogo) | tableta |
| `startVisualizer` | — | `bool` — `Visualizer(0)` (mezcla global); emite eventos `fft`. false sin permiso o sin soporte | tableta |
| `stopVisualizer` | — | — (también se libera al destruir la Activity) | tableta |
| `getLaunchableApps` | — | `[{package, label, icon: Uint8List? (PNG 96 px)}]` ordenado por `label`, sin esta app | tableta |
| `launchApp` | `{package, background: bool = true, delayMs: int = 1500}` | `bool` (se abrió); con `background` vuelve a traer esta app al frente tras `delayMs` | tableta |
| `bringToFront` | — | — (`REORDER_TO_FRONT` + `moveTaskToFront`) | tableta |
| `consumeBootLaunch` | — | `bool` (true una sola vez si la abrió `BootReceiver`, que ya lanzó la app acompañante) | tableta |
| `setHotspotAutoConnect` | `{ssid, password, enabled}` (`password` vacío = red abierta; si no, 8–63 caracteres) | `{ok, method: 'suggestion'\|'legacy'\|'none', error: String?}` — API 29+ `WifiNetworkSuggestion` (reemplaza la del mismo SSID; `enabled:false` la quita); < 29 `WifiConfiguration` guardada. `error` es un texto en español apto para mostrar, con el código entre paréntesis (p. ej. `(appDisallowed)`) | celular |
| `getWifiStatus` | — | `{connected: bool, ssid: String?}` (ssid null sin permiso/servicio de ubicación) | celular |
| `getLinkDiagnostics` | — | `{lines: [String], networks: [red]}` — `lines`: registro nativo circular (≤ 150, `HH:mm:ss.SSS mensaje`): celular = beacons enviados (resumen por red cada 60 s), marcados al carro y su resultado (clase de error), `car_beacon` recibidos, pantallas aceptadas/cerradas/duplicadas, cambios de red, hotspot recibido; tableta = intentos de hotspot, multicast lock. `networks` = mismo formato que `getWifiNetworks`. El Dart de cada lado agrega su propio registro | ambos |
| `clearLinkDiagnostics` | — | — (vacía el registro nativo) | ambos |
| `getWifiNetworks` | — | `[{name, iface, ip, prefix, gateway, broadcast, hasInternet, isDefault, isWifi, isHotspot}]` — redes de ConnectivityManager + LinkProperties (`hasInternet` = INTERNET y VALIDATED; `isDefault` = red activa) más interfaces de hotspot sin objeto Network (`ap*`, `wlan1`, `swlan*`, `softap*`: `isHotspot: true`, `gateway` null) | ambos |

**Inicio automático**: `BootReceiver` (exportado, `RECEIVE_BOOT_COMPLETED`) escucha `BOOT_COMPLETED`,
`LOCKED_BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `MY_PACKAGE_REPLACED` y broadcasts "ACC on" de head units
(`android.intent.action.ACC_ON`, `com.fyt.boot.ACCON`, `com.microntek.bootcheck`,
`autochips.intent.action.QB_POWERON`). Lee `FlutterSharedPreferences`: `flutter.app_mode == "car"` y
`flutter.car_autostart == true` (Boolean); opcional `flutter.car_autostart_delay` (segundos, Long, default 3).
Tras el delay lanza `MainActivity` (`FLAG_ACTIVITY_NEW_TASK`). En Android 10+ requiere `SYSTEM_ALERT_WINDOW`
(se intenta igual sin el permiso; errores se registran con tag `PCP`).
**App acompañante**: si `flutter.car_companion_package` (String) no está vacío, tras el delay se abre esa app
primero y `MainActivity` `flutter.car_companion_delay` ms después (Long, default 1500, máx. 30000) para que
la nuestra quede al frente. Solo ocurre si el inicio automático está activo (mismas condiciones de arriba).

**Hotspot local**: mientras hay una reserva LocalOnlyHotspot activa corre `HotspotKeeperService`
(foreground, `connectedDevice`, notificación "Hotspot del carro activo"), porque Android apaga el hotspot
local cuando la app que lo pidió deja de estar en primer plano.

Claves de `FlutterSharedPreferences` leídas en nativo (prefijo `flutter.`): `app_mode`, `car_autostart`,
`car_autostart_delay`, `car_companion_package`, `car_companion_delay`; en el celular `phone_car_ip` (String,
IP manual del carro para el marcador v2; vacío/ inválido = no se usa).
**Escritas en nativo** (celular, al recibir `hotspot` de la tableta, solo si SSID o clave cambiaron):
`phone_car_hotspot_ssid`, `phone_car_hotspot_password` (String) y `phone_car_hotspot_autoconnect = true`
(Boolean); además se llama a la lógica de `setHotspotAutoConnect`. Como `SharedPreferences` de Dart cachea en
memoria, la UI debe hacer `reload()` al recibir el evento `hotspotReceived`.
Identificador de instalación (`id` de `hello`/`beacon`): `SharedPreferences("pcp_native")["install_id"]` (UUID).

`EventChannel("pcp/events")` — un único stream de `Map` con campo `type`:

| `type` | Campos |
|--------|--------|
| `transmitterStatus` | `running` (bool), `port`, `ips: [String]`, `clients: [{device, transport: "wifi"\|"bt", address, origin: "accept"\|"dial"\|"bt", id: String?}]` (`origin` dial = el celular marcó al carro; `id` = id del `hello` del carro), `session: {package, title, artist, playing}?`, `lyricsStatus`, `carHotspotSsid: String?` (guardado) |
| `hotspotReceived` | `ssid`, `ok` (bool, se registró la red), `error: String?` — el celular recibió `hotspot` de la tableta con datos nuevos y ya los guardó |
| `rfcomm` | `event`: `connected` (`name`, `address`) \| `line` (`data`: String JSON) \| `disconnected` (`reason`) |
| `localMedia` | `package`, `title`, `artist`, `album`, `durationMs`, `playing`, `positionMs`, `art` (`Uint8List?` PNG/JPEG) |
| `fft` | `bands: List<double>` (64, graves → agudos, log-espaciadas 30 Hz–16 kHz, 0..1 con auto-ganancia lenta y suavizado de caída), `rms: double` (0..1, auto-ganancia). ≤ 30 fps; la mayoría de los equipos captura a 20 Hz como máximo |

### §2 v3 — tableta (mantener al frente, burbuja, conectividad) y ambos (actualizaciones, copias)

Implementado en `CarFeatures.kt` (MainActivity delega con una línea al inicio de su `handle`).

| Método | Args | Retorno | Lado |
|--------|------|---------|------|
| `getAppVersion` | — | `{versionName, versionCode (long, el del APK instalado: con split-per-abi incluye 1000×ABI), abi (SUPPORTED_ABIS[0]), package, installedAt (ms, lastUpdateTime)}` | ambos |
| `checkForUpdate` | — | `{available, versionName, versionCode, notes, htmlUrl, apkUrl, apkSize, apkName, abi, tag, prerelease, publishedAt, error?}` — ver "Actualizaciones" abajo. `error`: `network` \| `http_<código>` \| `rateLimited` \| `parse` \| `noReleases` \| `noAsset` (con error, solo `available:false`) | ambos |
| `downloadAndInstallUpdate` | `{apkUrl}` (https) | `bool` — true si quedó en marcha el instalador del sistema (el usuario confirma). Responde al terminar la descarga | ambos |
| `canInstallPackages` | — | `bool` (`canRequestPackageInstalls()`; true bajo API 26) | ambos |
| `openInstallPermissionSettings` | — | — (`ACTION_MANAGE_UNKNOWN_APP_SOURCES` de esta app → Seguridad → info de la app) | ambos |
| `saveBackupFile` | `{json, name = 'pixel-car-player-config.json'}` | `String?` ruta absoluta legible. API 29+: MediaStore `Documents/PixelCarPlayer/` (sobrescribe si el archivo es nuestro; uno ajeno o de una instalación anterior → MediaStore agrega ` (1)` y se devuelve el nombre real). API < 29: `Documents/PixelCarPlayer/` público (pide `WRITE_EXTERNAL_STORAGE`). Si falla: `Android/data/<pkg>/files/Documents/PixelCarPlayer/` (se borra al desinstalar). null si todo falla | ambos |
| `pickBackupFile` | — | `String?` contenido (UTF-8, ≤ 5 MB) del archivo elegido con `ACTION_OPEN_DOCUMENT` (`application/json`, `text/*`, `application/octet-stream`; respaldo `GET_CONTENT`), null si se canceló | ambos |
| `getConnectivityStatus` | — | `{btEnabled, btPermission, btDevices: [{name, address, profiles: [String]}], wifiEnabled, wifiConnected, wifiSsid: String?, hotspotOn: bool?, hotspotClients: int?}` — `profiles` ⊂ `a2dp`, `a2dpSink` (11: el radio recibe audio del celular), `headset`, `headsetClient` (16: HFP del radio), `avrcpController` (12), `acl` (enlace conectado sin perfil conocido: broadcasts ACL + `BluetoothDevice.isConnected()` oculto). `wifiSsid` null sin permiso/servicio de ubicación. `hotspotClients`: `SoftApCallback` (API 30+, casi siempre bloqueado) → cantidad de IPs vecinas (ARP) si > 0 → null = desconocido; 0 con hotspot apagado | tableta |
| `startConnectivityWatch` / `stopConnectivityWatch` | — | — (receivers BT/Wi-Fi/AP + NetworkCallback; emite `connectivity` al empezar y en cada cambio, antirrebote 500 ms, solo si cambió algo) | tableta |
| `hasUsageAccess` | — | `bool` (AppOps `GET_USAGE_STATS`) | tableta |
| `openUsageAccessSettings` | — | — (`ACTION_USAGE_ACCESS_SETTINGS` con/sin `package:` → info de la app) | tableta |
| `setKeepInFront` | `{enabled, packages: [String], anyApp: bool, delayMs: int (0–60000, def. 1500), includeLauncher?: bool (def. false)}` | `bool` — true si el servicio quedó corriendo (o si se desactivó) | tableta |
| `setFloatingBubble` | `{enabled, size: int dp (40–160, def. 64), opacity: double (0.2–1, def. 0.95), showTitle?: bool (def. true)}` | `bool` — false si falta "mostrar sobre otras apps" (la config se guarda igual) | tableta |
| `updateFloatingBubble` | `{title, artist, art: Uint8List?, playing}` | — (se guarda aunque la burbuja no esté visible) | tableta |

**Mantener al frente** (`KeepFrontService`, foreground `specialUse`, notificación "Pixel Car Player se
mantiene al frente", canal `pcp_keep_front` de importancia baja). Cada ~1 s lee la app en primer plano con
`UsageStatsManager.queryEvents` (último `ACTIVITY_RESUMED`). Dispara si no hay ninguna Activity nuestra en
resumed y la app al frente: está en `packages` (siempre, aunque sea el launcher), o `anyApp` y no es
Ajustes / SystemUI / instalador / permisos / DocumentsUI / Play Store, ni el launcher (salvo
`includeLauncher`: apretar Inicio = el usuario quiere salir). Tras `delayMs` con la misma app al frente →
`AppLauncher.bringToFront` (Android 10+ necesita "mostrar sobre otras apps"). **Sin acceso de uso** solo
funciona con `anyApp`: dispara cuando MainActivity deja de estar al frente (sin saber qué app la tapó).
No pelea con el usuario: si tuvo que volver 3 veces en 60 s por la misma app, deja de insistir con esa app
5 min. Además se pausa (hasta que MainActivity vuelve) cuando la propia app abre Ajustes, diálogos de
permisos, el selector de copias, el instalador o `launchApp` con `background:false` (si MainActivity sale
del frente ≤ 8 s después de esa llamada).

**Burbuja** (overlay `TYPE_APPLICATION_OVERLAY` dentro del mismo servicio): portada recortada en forma de
"cookie" de 9 lóbulos que gira mientras `playing`, título · artista en marquesina debajo; tocar = traer
Pixel al frente; mantener presionado y arrastrar = moverla (posición guardada). Visible solo mientras
ninguna Activity nuestra está al frente.

**Prefs nativas** `SharedPreferences("pcp_car")` (las lee `BootReceiver` para reanudar el servicio al
encender / tras actualizar, independiente de `car_autostart`): `keep_front_enabled` (bool),
`keep_front_packages` (StringSet), `keep_front_any_app` (bool), `keep_front_delay_ms` (long),
`keep_front_include_launcher` (bool), `bubble_enabled` (bool), `bubble_size` (int dp), `bubble_opacity`
(float), `bubble_show_title` (bool), `bubble_x` / `bubble_y` (int px, posición de la burbuja).

**Actualizaciones**: `GET https://api.github.com/repos/SantiagortegaDev/pixel-car-player/releases?per_page=30`
(incluye prereleases, ignora drafts). Nombre de asset esperado:
`pixel-car-player-<versionName>-<versionCode>-<abi>.apk`, `abi` ∈ `arm64-v8a` \| `armeabi-v7a` \| `x86_64` \|
`x86` \| `universal`. Por release se elige el asset de la ABI exacta (en el orden de `SUPPORTED_ABIS`) y si
no, `universal`; cualquier otro `.apk` cuenta como universal sin versión. Gana el release más nuevo por
versionName (numérico por partes, "1.10" > "1.9") y luego versionCode **base** (`code % 1000` si ≥ 1000,
por el +1000×ABI de `--split-per-abi`). Si ningún release trae versionCode en el nombre, se usa el
`published_at` más nuevo y `available` = publicado > `installedAt` + 10 min. La descarga va a
`cacheDir/updates/update.apk`, se verifica tamaño (`Content-Length`) y que el APK sea de este paquete, y se
instala con una sesión de `PackageInstaller` (respaldo: `ACTION_INSTALL_PACKAGE` con `FileProvider`
`<pkg>.fileprovider`). Solo conserva los datos si está firmado con la misma clave (si no:
`updateState` error `signature`).

Eventos nuevos en `pcp/events`:

| `type` | Campos |
|--------|--------|
| `connectivity` | mismos campos que `getConnectivityStatus` |
| `updateProgress` | `received` (bytes), `total` (bytes, -1 si se desconoce); ≤ 4 por segundo y uno final |
| `updateState` | `state`: `downloading` \| `installing` \| `error`; `error?`: `busy`, `badUrl`, `installPermission` (pedir `openInstallPermissionSettings`), `http_<código>`, `network`, `incomplete`, `invalidApk`, `installer`, `cancelled` (el usuario rechazó), `signature` (firma distinta / incompatible), `storage`, u otro texto del sistema |

### §2 v3 — celular (emparejamiento, arranque automático): notas de implementación

Métodos según `native_bridge.dart` (sección v3). Detalles que fija el nativo:

- **Tokens**: `SharedPreferences("pcp_native")["paired_cars"]` = JSON `{carId: {token, name, pairedAt}}`
  (`pairedAt` en ms epoch). `getPairedCars` → `[{id, name, pairedAt}]`, más reciente primero. `forgetCar`
  también cierra las sesiones vivas de ese carro (si se reconecta, vuelve a pedir emparejamiento).
- **Eventos**: `{type:'pairNeeded', carId, carName}` (se envió `pair_request`); `{type:'pairResult', carId,
  ok, reason?}` (`reason`: lo que mande la tableta: `code` \| `expired` \| `busy`). Con `expired` el celular
  pide otro código solo (nuevo `pairNeeded`). `submitPairCode` devuelve false si no hay una sesión con ese
  carro esperando código (o el servicio no corre); el código se limpia a dígitos (4–10).
- Si hay token pero el carro no manda `auth` en ~6 s tras su `hello`, se pide emparejar. Un carro sin
  `nonce` en su `hello` (versión vieja) no puede autenticarse: con "Requerir emparejamiento" queda sin datos.
- `transmitterStatus.clients[]` agrega `authenticated` (bool) y `pairing` (bool, esperando código).
- **Reglas**: `pcp_native["autostart_rules"]` (JSON de las reglas). `stopAfterMinutes` por defecto 2,
  rango 0–240. MACs en mayúsculas; SSID exacto (distingue mayúsculas). `associateCarDevice` agrega la
  dirección asociada a `btAddresses` y empieza a observar su presencia (API 31+). Sin `address` usa la
  primera de `btAddresses`; sin ninguna muestra el selector del sistema. `error`: `cancelled`,
  `unsupported`, `noDevice`, `superseded` o el texto de CompanionDeviceManager.
- `getAutoStartStatus` agrega `associated: [String]` (MACs asociadas con CompanionDeviceManager); `reason`
  es un texto en español apto para mostrar.
- Con reglas activas, el transmisor se detiene solo tras 10 min sin pantalla si ninguna regla coincide.
  Si Android 12+ no deja iniciarlo desde segundo plano, se publica la notificación "Toca para transmitir
  al carro" (canal `pcp_autostart`). Wi-Fi: el SSID solo se lee con ubicación concedida (en segundo plano,
  Android 10+ exige ubicación "todo el tiempo"); si no, esa regla no dispara.

## 3. Paquete / ids

- applicationId: `com.santiagortega.pixelcarplayer`
- Nombre visible: **Pixel Car Player**
- Kotlin package: `com.santiagortega.pixelcarplayer`
