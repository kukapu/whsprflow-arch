# Wispr Flow en Arch Linux / Hyprland

Este proyecto construye **Wispr Flow 1.6.447** para Linux a partir del paquete
oficial de Windows. No es una reimplementacion de Whisper ni usa Wine: conserva
el cliente Electron, el login, la cuenta Pro y los servicios cloud de Wispr, y
sustituye solo la integracion Win32 por un helper Linux de codigo abierto.

El repositorio no redistribuye el cliente propietario. `install.sh` lo descarga
del CDN oficial y exige su SHA-256. El unico binario incluido es el helper Linux
abierto (Unlicense), auditado y reproducible desde su commit fijado.

La licencia 0BSD de este repositorio cubre solamente el soporte, los scripts, la
documentacion y el packaging escritos para el proyecto. No cubre ni concede
derechos sobre el cliente propietario de Wispr, que nunca se guarda en Git.

Wispr no publica ni soporta oficialmente una version Linux. El resultado es un
port comunitario y puede romperse con una futura actualizacion del servicio.

## Dos rutas de instalacion distintas

### Ruta 1: repositorio completo (disponible hoy)

Esta es la ruta funcional y validada actualmente para otra maquina Arch Linux
x86_64 con Hyprland: copia o clona **todo** el repositorio y ejecuta
`./install.sh` como se explica mas abajo. El instalador obtiene los artefactos,
ensambla el runtime y hace la integracion de sistema y de usuario.

Siguen siendo especificos de cada maquina y usuario: disponer de una sesion
Hyprland activa, acceso a `sudo` y red durante la instalacion, volver a iniciar
sesion si cambia el acceso a dispositivos, completar el login de Wispr,
seleccionar el microfono y realizar la validacion final de dictado. La
integracion automatica soporta tanto `hyprland.conf` como la entrada Lua
`hyprland.lua` de Hyprland >= 0.55 (Omarchy 4).

### Ruta 2: AUR

El paquete `wispr-flow-hyprland` esta publicado en
<https://aur.archlinux.org/packages/wispr-flow-hyprland>. En una instalacion
nueva, la ruta completa es:

```bash
yay -S wispr-flow-hyprland
wispr-flow --setup
wispr-flow --doctor
```

El paquete descarga el cliente directamente desde Wispr, verifica todos los
hashes y construye localmente el mismo runtime parcheado. `pacman` gestiona sus
archivos, actualizaciones y desinstalacion; el login, microfono y preferencias
siguen siendo propios de cada usuario y equipo.

`wispr-flow --setup` se ejecuta como el usuario normal, nunca con `sudo`. Crea o
repara una configuracion Linux valida, oculta Flow Bar en Hyprland, registra el
callback `wispr-flow:` con `xdg-mime` cuando esta disponible e instala solamente
en Hyprland las reglas gestionadas del compositor.

El paquete AUR existente `wispr-flow-appimage` tambien proporciona y entra en
conflicto con `wispr-flow`. Por ello no puede instalarse a la vez que
`wispr-flow-hyprland`: hay que escoger una de las dos variantes. Este proyecto
no usa `replaces`, por lo que el cambio nunca se realiza silenciosamente.

Si esta maquina ya se instalo mediante `./install.sh`, no superpongas ambas
rutas. Desde el repositorio ejecuta primero `./uninstall.sh` **sin** `--purge` y
despues instala el paquete AUR. Asi se conservan la cuenta y preferencias de
`~/.config/Wispr Flow/`, pero `pacman` pasa a ser el unico propietario de los
archivos del sistema.

## Que necesitas copiar para la ruta del repositorio

No descargues una AppImage, un instalador de Windows ni Electron manualmente.
`install.sh` descarga y construye todo lo necesario. Debes conservar junta la
carpeta completa de este proyecto; no copies solamente `install.sh`, porque el
instalador tambien utiliza los scripts de `bin/`.

La carpeta minima debe contener:

```text
whsprflow-arch/
|-- assets/
|   |-- UNLICENSE
|   `-- wispr-flow-linux-helper-x86_64
|-- install.sh
|-- uninstall.sh
|-- bin/
|   |-- wispr-flow
|   `-- wispr-flow-configure
|-- patches/
|   |-- helper/
|   |   |-- terminal-paste.patch
|   |   `-- uinput.rs
|   `-- linux-runtime-fixes.sh
|-- scripts/
|   |-- assemble-app.sh
|   `-- build-helper.sh
|-- packaging/
|   `-- aur/
|-- tests/
|   `-- smoke.sh
|-- LICENSE
|-- REUSE.toml
`-- README.md
```

## Requisitos

- Arch Linux x86_64 actualizado.
- Una sesion de Hyprland iniciada con tu usuario normal.
- Conexion a Internet durante la instalacion.
- Acceso a `sudo` para instalar paquetes, la aplicacion y las reglas udev.
- Aproximadamente 2.5 GB libres durante la construccion.
- Una cuenta de Wispr para iniciar sesion al terminar.

No ejecutes el instalador ni la aplicacion completa con `sudo`. El propio script
pedira `sudo` solamente para las operaciones que lo necesitan.

## Instalacion con el repositorio completo

1. Abre una terminal dentro de Hyprland y entra en la carpeta del proyecto. Usa
   la ruta real en la que tengas `whsprflow-arch`:

   ```bash
   cd /ruta/donde/tienes/whsprflow-arch
   ```

2. Comprueba que estas en la carpeta correcta:

   ```bash
   ls
   ```

   Debes ver, como minimo, `assets`, `bin`, `patches`, `scripts`, `tests`,
   `install.sh`, `uninstall.sh` y `README.md`.

3. Da permisos de ejecucion a los scripts:

   ```bash
   chmod +x install.sh uninstall.sh bin/* patches/*.sh scripts/* tests/*
   ```

4. Ejecuta la prueba local de los scripts:

   ```bash
   ./tests/smoke.sh
   ```

   El resultado debe terminar con `Smoke tests OK`.

5. Cierra cualquier instancia anterior de Wispr Flow y ejecuta la instalacion:

   ```bash
   ./install.sh
   ```

6. Introduce tu clave de `sudo` cuando se solicite y confirma la instalacion de
   paquetes de `pacman`. El instalador hace automaticamente todo esto:

   - instala las dependencias de Arch, incluidos `asar`, XWayland y
     `wl-clipboard`;
   - descarga el cliente oficial de Wispr Flow `1.6.447`;
   - descarga Electron Linux `42.3.0`;
   - usa el helper Linux abierto `0.1.2`, parcheado desde el commit fijado;
   - descarga el modulo SQLite Linux compatible;
   - comprueba el SHA-256 y la arquitectura de cada binario;
   - aplica y verifica los parches Linux;
   - instala la aplicacion en `/opt/wispr-flow`;
   - instala el comando `/usr/local/bin/wispr-flow`;
   - registra el protocolo de login `wispr-flow:` y la entrada del menu;
   - configura `Ctrl+Shift` como push-to-talk si no existe un atajo valido;
   - usa Wayland nativo con indicador de grabacion transitorio en Hyprland;
   - reproduce localmente los sonidos de inicio y fin si estan habilitados;
   - instala reglas reversibles para que Flow Hub sea flotante y centrado,
     en `hyprland.lua` (sesiones Lua) o `hyprland.conf`;
   - instala las reglas udev para `/dev/uinput` y los teclados;
   - anade tu usuario al grupo `input` si todavia no pertenece a el y registra
     que esa membresia fue creada por este instalador.

   Las descargas verificadas quedan en `~/.cache/whsprflow-arch`, de modo que una
   reinstalacion no tiene que descargarlas otra vez. Los directorios temporales
   de construccion se borran automaticamente.

### Arquitectura del ensamblado

La construccion esta separada de la instalacion del sistema.
`scripts/assemble-app.sh` recibe mediante flags explicitos el NUPKG, Electron,
SQLite, el helper y un checkout local del port; usa el comando `asar` del
sistema y publica solamente un runtime directo ya verificado (`wispr-flow`,
`resources`, etc.). No descarga artefactos, no clona repositorios, no usa
`sudo`/`pacman` ni escribe en el HOME real. El directorio de salida no puede
existir previamente.

`install.sh` sigue verificando y obteniendo los inputs fijados, llama a ese
ensamblador con `/usr/bin/asar` y despues integra el runtime bajo el layout
existente `usr/lib/wispr-flow`. Por tanto, el ensamblado reutilizable necesita
el paquete Arch `asar`; ya no descarga una copia temporal con un gestor de
paquetes JavaScript.

7. Comprueba que la salida termina de forma parecida a esta:

   ```text
   ==> Instalacion terminada
   Version:      1.6.447
   Tipo:         system
   Ejecutable:   /usr/local/bin/wispr-flow
   ```

8. Si el instalador ha anadido tu usuario al grupo `input`, cierra completamente
   la sesion de Hyprland y vuelve a entrar. No basta con cerrar la terminal. No
   es necesario reiniciar el equipo, aunque reiniciarlo tambien sirve.

## Comprobar la instalacion

Ya dentro de una sesion nueva de Hyprland, ejecuta como usuario normal:

```bash
command -v wispr-flow
wispr-flow --doctor
```

El primer comando debe mostrar `/usr/local/bin/wispr-flow`. En el diagnostico,
comprueba especialmente estas lineas:

- `/dev/uinput` debe ser escribible;
- al menos un dispositivo de teclado debe ser legible;
- el helper Linux debe arrancar correctamente;
- Electron debe indicar la version `42.3.0`;
- el callback `wispr-flow:` debe aparecer registrado;
- el atajo PTT debe aparecer como `Ctrl+Shift`.

Un aviso de AT-SPI al principio de la sesion puede ser recuperable; los fallos de
`/dev/uinput`, teclado, helper o callback deben corregirse antes de usar Flow.
Si los permisos de entrada siguen fallando despues de volver a entrar, ejecuta
de nuevo `./install.sh` desde la carpeta del proyecto y repite el diagnostico.

## Primer inicio y login

1. Inicia la aplicacion desde el menu de Hyprland o desde una terminal:

   ```bash
   wispr-flow
   ```

2. Pulsa la opcion de iniciar sesion. Flow abrira el navegador.
3. Completa el login en la web de Wispr.
4. El navegador debe abrir automaticamente un enlace `wispr-flow:` que vuelve a
   la aplicacion. No copies tokens ni edites archivos manualmente.
5. Selecciona el microfono en Flow y prueba el dictado manteniendo
   `Ctrl+Shift`.
6. Prueba primero en un editor de texto sencillo y despues en tus aplicaciones
   Wayland habituales.

Para consultar el registro si algo falla:

```bash
wispr-flow --logs
```

El perfil, la sesion y las preferencias se guardan en
`~/.config/Wispr Flow/`. Reinstalar conserva ese directorio.

## Hyprland y segundo plano

Electron 42 no implementa `setIgnoreMouseEvents()` en Wayland nativo, pero eso
solo afecta a la Flow Bar persistente. Con Flow Bar desactivada, el default en
Hyprland es Wayland nativo con el indicador de grabacion como ventana
transitoria: aparece al dictar, se desmapea en `Idle`, `Error` o `Dismissed`
(sin superficie invisible que capture clics en reposo) y escala correctamente
con el monitor. Solo con `--flow-bar on` el wrapper pasa a XWayland para
mantener el click-through de la barra. El helper sigue usando las APIs Wayland
para portapapeles, entrada global e inyeccion de teclas. Para ocultar tambien
el indicador durante la grabacion:

```bash
WISPR_FLOW_TRANSIENT_STATUS_WINDOW=0 wispr-flow
```

El indicador transitorio conserva el click-through original de la app
(`setIgnoreMouseEvents` de Electron 42; su `forward` solo funciona en X11, por
lo que los botones del menu no responden en Wayland nativo). Se puede ajustar
su geometria con variables de entorno: `WISPR_FLOW_STATUS_ZOOM` (escala, por
defecto `1.45`), `WISPR_FLOW_STATUS_Y` (fraccion de altura de pantalla para
el centro de la ventana, por defecto `0.83`, deja el pill a un sexto del borde
inferior), `WISPR_FLOW_STATUS_W`/`WISPR_FLOW_STATUS_H` (tamaño absoluto en px)
y `WISPR_FLOW_STATUS_CLICKABLE=1` para probar el modo interactivo
experimental. La posicion se aplica en la propia funcion de geometria de la
app, de modo que el reposicionamiento periodico durante el dictado la
respeta.

Los sonidos de inicio y fin se envian al renderer local y respetan la opcion de
sonidos de Flow. Al pegar, el helper usa `Ctrl+V` normalmente y
`Ctrl+Shift+V` cuando la ventana activa de Hyprland es un terminal conocido,
incluido Warp.

Las reglas gestionadas solo coinciden con clase `wispr-flow` y titulo `Hub` o
`Flow Hub`. No afectan las ventanas Status, Context Menu ni Scratchpad. En
sesiones Lua se guardan en `~/.config/hypr/wispr-flow.lua` y se cargan con un
bloque `dofile` gestionado en `hyprland.lua`; en sesiones `.conf` siguen en
`~/.config/hypr/wispr-flow.conf`. El configurer nunca sobrescribe un archivo
ajeno con esos nombres y conserva los symlinks de la configuracion. Los
comandos `--show`, `--hide` y `--background` usan la sintaxis de dispatch Lua
en Hyprland >= 0.55 y la clasica en versiones anteriores.

Comandos utiles:

```bash
wispr-flow --setup         # configuracion inicial para paquetes del sistema
wispr-flow --fix-shortcut  # repara un atajo Fn heredado de macOS
wispr-flow --flow-bar on   # barra compacta persistente (usa XWayland)
wispr-flow --flow-bar off  # indicador de grabacion transitorio (Wayland nativo)
wispr-flow --show          # trae Flow Hub al workspace actual
wispr-flow --hide          # envia Flow Hub a special:wispr-flow
wispr-flow --background    # inicia y deja Flow listo sin Hub visible
wispr-flow --status        # cuenta Electron principal y helper
wispr-flow --stop          # cierre limpio; termina solo esta instalacion
wispr-flow --reset-input   # recuperacion segura ante entrada atascada
wispr-flow --autostart on
wispr-flow --autostart off
wispr-flow --logs
```

Para forzar temporalmente otro backend:

```bash
WISPR_FLOW_BACKEND=wayland wispr-flow
WISPR_FLOW_BACKEND=x11 wispr-flow
WISPR_FLOW_BACKEND=auto wispr-flow
```

 `--stop` y `--reset-input` identifican procesos por la ruta exacta de sus
 ejecutables, intentan primero el cierre limpio, escalan a `TERM`/`KILL` solo si
 es necesario y comprueban que desaparezca el teclado virtual de Wispr. No usan
 `pkill` por nombre ni reinician Hyprland.

## Helper corregido y reproducible

El helper upstream `v0.1.2` restauraba mediante `key-down` virtual los
modificadores fisicos que encontraba pulsados al pegar. Como el helper no recibe
necesariamente el futuro `key-up` fisico, Ctrl, Shift, Alt o Super podian quedar
atascados. Ademas, un error intermedio podia saltarse parte de la limpieza.

`patches/helper/uinput.rs` cambia esa politica: libera todas las teclas
virtuales aunque haya errores y nunca restaura virtualmente un modificador
fisico. `patches/helper/terminal-paste.patch` detecta la clase de la ventana
activa en Hyprland para usar el acorde de pegado correcto. El binario incluido
procede exactamente de:

```text
Repositorio: https://github.com/wispr-flow-linux/helper.git
Commit:      fa93fcf31d9ee7a9591a8dce1852f815d1b0dec5
Rust:        1.96.0
SHA-256:     5f069506ccf51964f05ba6b06b7a1bfbb42cd2a5d64437c965abba628c4b45b0
```

Para reproducirlo, usa Rust `1.96.0`; el script clona el commit, verifica el
archivo upstream y los parches, ejecuta 13 tests, `clippy`, build release y exige
el mismo SHA antes de escribir el resultado:

```bash
./scripts/build-helper.sh /tmp/wispr-flow-linux-helper
```

## Seguridad

En Wayland, el helper necesita escribir en `/dev/uinput` para insertar texto y
leer eventos de teclado para el atajo global. La regla limita la lectura a los
dispositivos marcados por udev como teclado, pero cualquier proceso ejecutado
con tu usuario podria aprovechar esos permisos. Es una limitacion conocida del
port hasta que disponga de un backend estable de GlobalShortcuts portal.

La instalacion de usuario sin sandbox SUID esta disponible solo como fallback:

```bash
./install.sh --user
```

La instalacion conserva `~/.config/Wispr Flow/`, incluidas sesion y preferencias.
No compartas ese directorio ni `~/.cache/wispr-flow/launcher.log`: pueden contener
informacion privada de cuenta, aplicaciones usadas o dictados.

## Desinstalar

```bash
./uninstall.sh
./uninstall.sh --purge  # tambien borra sesion local, preferencias y cache
```

El desinstalador detiene primero los procesos por ruta exacta, retira reglas
Hyprland/autostart, elimina la regla udev y revoca los ACL creados. Si esta
version del instalador fue quien anadio tu usuario al grupo `input`, tambien lo
retira; una membresia preexistente o heredada de una version antigua se conserva
por seguridad. Tras retirar una membresia debes cerrar la sesion para que deje de
estar activa en procesos ya iniciados.

## Verificacion

```bash
./tests/smoke.sh
```

La prueba real realizada durante el desarrollo confirmo: Electron bajo
XWayland con Status transitorio,
version `1.6.447`, ASAR extraible sin referencias Windows rotas, helper Linux
reproducible, una sola instancia, Hub oculto en el workspace especial y cierre
sin procesos ni teclado virtual restantes. La prueba final de entrada requiere
dictar en tu sesion real: completa al menos 20 ciclos PTT, incluyendo cancelar
uno y detener Flow durante una prueba controlada, y confirma que ningun
modificador queda activo.

## Fuentes

- Cliente oficial: <https://dl.wisprflow.com/wispr-flow/win32/x64/RELEASES>
- Port Linux: <https://github.com/wispr-flow-linux/wispr-flow-linux>
- Helper Linux: <https://github.com/wispr-flow-linux/helper>
- Requisitos oficiales: <https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements>
