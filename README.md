# r36-link-lan

RetroArch netplay between two R36 handhelds over a direct ethernet cable. No router, no WiFi.

**[English](#english)** · **[Español](#español)**

---

## English

### What it is

A single script that turns a regular ethernet cable into a link between two consoles. With the link active, any RetroArch netplay works just like it does over WiFi, but without a router, without a phone hotspot, without a WiFi dongle, and with lower latency.

### Requirements

- Two consoles running **dArkOSen** (tested on R36S and R36H). It should work on any ArkOS-based firmware that uses NetworkManager, but that isn't verified yet.
- **Two** USB-C to ethernet adapters, one per console.
- An OTG adapter if your ethernet adapter is USB-A.
- Any ethernet cable.
- For netplay: the same ROM and the same RetroArch core on both consoles.

### Installation

1. Copy `en/Link LAN.sh` to the `/roms/tools` folder.
2. Do the same on the second console.

If you edit the script on Windows, make sure your editor saves it with **LF** line endings, not CRLF. In VS Code it's in the bottom-right corner, in the status bar. CRLF line endings break bash scripts with very confusing errors.

### First-time setup

On each console, open **Tools → Link LAN**. The first time, it asks which address that console takes:

- On one, pick **1** → `10.9.9.1`
- On the other, pick **2** → `10.9.9.2`

You only do this once. The profile stays saved.

### Playing

1. Connect the cable between the two adapters.
2. On **both** consoles: **Tools → Link LAN → Activate link**. The script waits for the cable, brings up the link, and pings the other console to confirm they can see each other.
3. In RetroArch, on both consoles: **Settings → Network → Netplay**, turn off **Use Relay Server** and **Publicly Announce Netplay**. With the relay on, traffic goes out to an internet server and back, which is slow and simply doesn't work here.
4. On the host console: load the game → Quick Menu → **Netplay → Start Netplay Host**.
5. On the other one: load the same game → **Netplay → Connect to Netplay Host** → type the host's IP (`10.9.9.1` or `10.9.9.2`, whichever is hosting). Default port: `55435`.

### Going back to the router

Unplug the cable from the other console and plug it into the router. The normal DHCP profile comes up by itself.

The **Router mode** option in the menu is only needed in two cases: going back without unplugging, or recovering if you delete the DHCP profile.

Note: if you power on a console with the cable already connected to the other one, it will try DHCP for about 45 seconds before giving up. That's normal. Then activate the link as usual.

### Menu options

| Option | What it does |
|---|---|
| Activate link | Waits for the cable, brings up the static IP, and checks the other console |
| Router mode | Goes back to normal DHCP. Recreates the DHCP profile if it's missing |
| Delete link profile | Removes the link profile entirely. Last resort if something goes wrong |
| Diagnostics | Shows the network state on screen and saves it to a text file |

### Troubleshooting

**Diagnostics** shows everything on screen and saves it to `/roms/tools/linklan-diag.txt`, so you can read it from your PC without SSH. If you open an issue, attach that file. The script also keeps a log in `/roms/tools/linklan.log`.

**"No physical link".** Check the cable, that both adapters are plugged in, and that the other console is powered on.

**"No response" from the other console.** The link has to be activated on both consoles.

### Credits

- **djparent** ([dArkOSen](https://github.com/djparentx/dArkOSen-R36S)): gamepad handling and script structure adapted from his dArkOSen tools (MIT).
- **christianhaitian** ([dArkOS](https://github.com/christianhaitian/dArkOS)): the base system and the Tools-script conventions this builds on.
- **gptokeyb**: originally by Kris Henriksen (AnberPorts), ported to SDL2 by Nikolai Wuttke and Shanti Gilbert (EmuELEC), now maintained within [PortMaster](https://portmaster.games/).

### License

MIT. See [LICENSE](LICENSE).

---

## Español

### Qué es

Un único script que convierte un cable ethernet común en un enlace entre dos consolas. Con el link activo, cualquier netplay de RetroArch funciona igual que por WiFi, pero sin router, sin hotspot del celular, sin un dongle WiFi, y con menos latencia.

### Requisitos

- Dos consolas con **dArkOSen** (probado en R36S y R36H). Debería funcionar en cualquier firmware basado en ArkOS que use NetworkManager, pero todavía no está verificado.
- **Dos** adaptadores USB-C a ethernet, uno por consola
- Un adaptador OTG si tu adaptador ethernet es USB-A.
- Cualquier cable ethernet.
- Para el netplay: la misma ROM y el mismo core de RetroArch en las dos consolas.

### Instalación

1. Copiá `es/Link LAN.sh` a la carpeta `/roms/tools`
2. Lo mismo en la segunda consola.

Si editás el script en Windows, asegurate de que el editor lo guarde con saltos de línea **LF**, no CRLF. En VS Code está abajo a la derecha, en la barra de estado. Los saltos CRLF rompen los scripts de bash con errores muy confusos.

### Primera configuración

En cada consola, abrí **Tools → Link LAN**. La primera vez te pregunta qué dirección toma esa consola:

- En una, elegí **1** → `10.9.9.1`
- En la otra, elegí **2** → `10.9.9.2`

Se hace una sola vez. El perfil queda guardado.

### Para jugar

1. Conectá el cable entre los dos adaptadores.
2. En **las dos** consolas: **Tools → Link LAN → Activar link**. El script espera el cable, levanta el link y le hace ping a la otra consola para confirmar que se ven.
3. En RetroArch, en las dos consolas: **Settings → Network → Netplay**, apagá **Use Relay Server** y **Publicly Announce Netplay**. Con el relay encendido el tráfico sale a un servidor de internet y vuelve, que es lento y acá directamente no funciona.
4. En la consola host: cargá el juego → Quick Menu → **Netplay → Start Netplay Host**.
5. En la otra: cargá el mismo juego → **Netplay → Connect to Netplay Host** → escribí la IP del host (`10.9.9.1` o `10.9.9.2`, la que esté hosteando). Puerto por defecto: `55435`.

### Volver al router

Desenchufá el cable de la otra consola y enchufalo al router. El perfil DHCP normal se levanta solo.

La opción **Modo router** del menú solo hace falta en dos casos: volver sin desenchufar, o recuperarte si borrás el perfil DHCP.

Nota: si encendés una consola con el cable ya conectado a la otra, va a intentar DHCP unos 45 segundos antes de rendirse. Es normal. Después activás el link como siempre.

### Opciones del menú

| Opción | Qué hace |
|---|---|
| Activar link | Espera el cable, levanta la IP fija y verifica la otra consola |
| Modo router | Vuelve al DHCP normal. Recrea el perfil DHCP si falta |
| Borrar perfil link | Elimina el perfil link por completo. Último recurso si algo anda mal |
| Diagnóstico | Muestra el estado de la red en pantalla y lo guarda en un archivo de texto |

### Problemas comunes

**Diagnóstico** muestra todo en pantalla y lo guarda en `/roms/tools/linklan-diag.txt`, así que lo podés leer desde la PC sin SSH. Si abrís un issue, adjuntá ese archivo. El script también guarda un registro en `/roms/tools/linklan.log`.

**"Sin link físico".** Revisá el cable, que los dos adaptadores estén conectados y que la otra consola esté encendida.

**"Sin respuesta" de la otra consola.** El link tiene que estar activado en las dos consolas.

### Créditos

- **djparent** ([dArkOSen](https://github.com/djparentx/dArkOSen-R36S)): el manejo del gamepad y la estructura del script están adaptados de sus herramientas de dArkOSen (MIT).
- **christianhaitian** ([dArkOS](https://github.com/christianhaitian/dArkOS)): el sistema base y las convenciones de scripts de Tools sobre las que se apoya esto.
- **gptokeyb**: originalmente de Kris Henriksen (AnberPorts), portado a SDL2 por Nikolai Wuttke y Shanti Gilbert (EmuELEC), hoy mantenido dentro de [PortMaster](https://portmaster.games/).

### Licencia

MIT. Ver [LICENSE](LICENSE).
