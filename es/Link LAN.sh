#!/bin/bash
# =======================================================
# Link LAN - Netplay por cable entre dos consolas
# =======================================================
# Conecta dos consolas por cable ethernet directo, sin
# router ni WiFi, usando IPs fijas (10.9.9.1 y 10.9.9.2).
#
# Se usa el rango 10.x porque es el unico privado (RFC 1918)
# con primer octeto de dos digitos: 8 caracteres es lo mas
# corto posible de tipear en el teclado en pantalla de
# RetroArch. El 9.9 evita chocar con redes hogarenas, que
# casi siempre usan 10.0.0.x, 10.1.1.x o 192.168.x.x.
#
# Requiere: un adaptador USB-ethernet en cada consola
#           y un cable de red entre ambas.
#
# El menu muestra siempre la IP asignada. Incluye
# diagnostico en pantalla, para no depender de SSH.
#
# Proyecto: r36-link-lan (licencia MIT)
# El manejo del gamepad (gptokeyb) esta adaptado de las
# herramientas de dArkOSen de djparent (MIT).
# =======================================================

# Se relanza con privilegios de root (nmcli los necesita)
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

export TERM=linux
CURR_TTY="/dev/tty1"
LINK="link"                      # perfil de IP fija
DHCP="Wired connection 1"        # perfil DHCP que crea NetworkManager solo
NET="10.9.9"                     # primeros tres octetos del link
LOG="/roms/tools/linklan.log"
DIAG="/roms/tools/linklan-diag.txt"
HEIGHT="14"
WIDTH="55"

# Detecta el nombre de la interfaz cableada (eth0, enx..., etc)
IFACE=$(ls /sys/class/net/ 2>/dev/null | grep -E '^(eth|enx)' | head -1)
[ -z "$IFACE" ] && IFACE="eth0"

echo "===== $(date) =====" >> "$LOG"
log() { echo "$1" >> "$LOG"; }

chmod 666 "$CURR_TTY" 2>/dev/null
printf "\e[?25l" > "$CURR_TTY"   # oculta el cursor
printf "\033[H\033[2J" > "$CURR_TTY"

# ---- Fuente grande, legible en la pantalla de 640x480 ----
setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz 2>/dev/null

# ---- Gamepad como teclado, para responder los dialogos ----
SCRIPT_NAME=$(basename "$0")
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
chmod 666 /dev/uinput 2>/dev/null
TMP_KEYS="/tmp/keys.gptk.$$"
cp /opt/inttools/keys.gptk "$TMP_KEYS" 2>/dev/null
if grep -q '^b = backspace' "$TMP_KEYS" 2>/dev/null; then
    sed -i 's/^b = .*/b = esc/' "$TMP_KEYS"
    sed -i 's/^a = .*/a = enter/' "$TMP_KEYS"
fi
pkill -9 -f gptokeyb 2>/dev/null
sleep 0.1
/opt/inttools/gptokeyb -1 "$SCRIPT_NAME" -c "$TMP_KEYS" > /dev/null 2>&1 &

# Limpieza al salir por cualquier via (incluidos los exit)
Cleanup() {
    pkill -9 -f gptokeyb 2>/dev/null
    rm -f "$TMP_KEYS"
    setfont /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz 2>/dev/null
    printf "\e[?25h" > "$CURR_TTY"
    printf "\033[H\033[2J" > "$CURR_TTY"
}
trap Cleanup EXIT

# Cuadro que espera a que presiones A para cerrarse
msg() { dialog --clear --title "Link LAN" --msgbox "$1" 11 $WIDTH > "$CURR_TTY" 2>&1; }
# Cuadro informativo sin espera (para procesos en curso)
info() { dialog --clear --title "Link LAN" --infobox "$1" 7 $WIDTH > "$CURR_TTY" 2>&1; }

# IP que realmente tiene la interfaz ahora mismo
CurrentIP() { ip -4 -br addr show "$IFACE" 2>/dev/null | awk '{print $3}'; }
# IP que tiene guardada el perfil link (aunque este apagado)
ProfileIP() { nmcli -g ipv4.addresses con show "$LINK" 2>/dev/null; }

LinkExists() { nmcli -t -f NAME con show 2>/dev/null | grep -qx "$LINK"; }
LinkActive() { nmcli -t -f NAME con show --active 2>/dev/null | grep -qx "$LINK"; }
DhcpExists() { nmcli -t -f NAME con show 2>/dev/null | grep -qx "$DHCP"; }
# Solo perfiles ethernet: los nombres de redes WiFi nunca se
# escriben en el log ni en el diagnostico (pueden revelar donde vivis).
EthProfiles() { nmcli -t -f NAME,TYPE con show "$@" 2>/dev/null | grep ':802-3-ethernet$' | cut -d: -f1 | tr '\n' ' '; }

log "interfaz: $IFACE"
log "carrier: $(cat /sys/class/net/$IFACE/carrier 2>&1)"
log "perfiles ethernet: $(EthProfiles)"
log "activas ethernet: $(EthProfiles --active)"

# =======================================================
# Crear el perfil de IP fija
# =======================================================
# Cada consola necesita una direccion distinta. El menu
# evita que las dos elijan la misma por accidente.
CreateProfile() {
    local CHOICE MYADDR
    CHOICE=$(dialog --clear --no-collapse \
        --backtitle "Link LAN" \
        --title "Primera configuracion" \
        --cancel-label "Cancelar" \
        --menu "Que numero toma esta consola?\n(la otra debe tomar el otro)" \
        11 $WIDTH 2 \
        "1" "Esta consola sera ${NET}.1" \
        "2" "Esta consola sera ${NET}.2" \
        2>&1 > "$CURR_TTY")

    if [ $? -ne 0 ] || [ -z "$CHOICE" ]; then
        log "creacion cancelada"
        return 1
    fi

    MYADDR="${NET}.${CHOICE}/24"
    log "creando perfil con $MYADDR en $IFACE"

    # never-default: evita que la consola intente salir a
    # internet por este cable. ipv6 ignore: acelera el arranque.
    nmcli con add type ethernet ifname "$IFACE" con-name "$LINK" \
        autoconnect no \
        ipv4.method manual \
        ipv4.addresses "$MYADDR" \
        ipv4.never-default yes \
        ipv6.method ignore >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        log "fallo al crear el perfil"
        msg "No se pudo crear el perfil de red."
        return 1
    fi
    msg "Perfil creado.\n\nEsta consola sera ${MYADDR%/*}\n\nRepeti en la otra con el otro numero."
    return 0
}

# =======================================================
# Devolver la interfaz a modo DHCP normal
# =======================================================
# Se usa al desactivar el link y al borrar el perfil.
# Si el perfil DHCP no existe (por ejemplo si el usuario lo
# borro desde el Wi-Fi Manager), primero se recrea.
RestoreDhcp() {
    nmcli con down "$LINK" >/dev/null 2>&1
    # Limpia cualquier IP estatica que haya quedado pegada
    ip addr flush dev "$IFACE" 2>/dev/null
    nmcli device set "$IFACE" managed yes >/dev/null 2>&1

    # Si el perfil DHCP no existe, se recrea. Sin el, el unico
    # perfil ethernet del sistema es "link", y NetworkManager lo
    # vuelve a activar solo.
    if ! DhcpExists; then
        log "perfil DHCP no existe, recreando"
        nmcli con add type ethernet ifname "$IFACE" con-name "$DHCP" \
            autoconnect yes ipv4.method auto >/dev/null 2>&1
    fi

    # Se activa por nombre, nunca con "device connect": ese comando
    # elige el mejor perfil disponible y reactivaria "link".
    nmcli con up "$DHCP" >/dev/null 2>&1
    sleep 1
    log "tras restaurar DHCP: ip=$(CurrentIP) estado=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^$IFACE:")"
}

# =======================================================
# Activar el link
# =======================================================
ActivateLink() {
    # NetworkManager rechaza activar un perfil sin link fisico,
    # asi que primero espera a que el cable este conectado.
    ip link set "$IFACE" up 2>/dev/null
    local i CARR MYIP PEER
    for i in $(seq 1 15); do
        [ "$(cat /sys/class/net/$IFACE/carrier 2>/dev/null)" = "1" ] && break
        dialog --clear --title "Link LAN" --infobox "Esperando el cable... ($i/15)" 7 $WIDTH > "$CURR_TTY" 2>&1
        sleep 1
    done

    CARR=$(cat /sys/class/net/$IFACE/carrier 2>/dev/null)
    log "carrier tras espera: $CARR"
    if [ "$CARR" != "1" ]; then
        log "sin carrier"
        msg "Sin link fisico.\n\nRevisa el cable, los adaptadores\ny que la otra consola este encendida."
        return 1
    fi

    info "Activando link..."
    nmcli con down "$DHCP" >/dev/null 2>&1
    if nmcli con up "$LINK" >/dev/null 2>&1; then
        MYIP=$(CurrentIP)
        # Deduce la direccion de la otra consola a partir de la propia
        case "$MYIP" in
            ${NET}.1/*) PEER="${NET}.2" ;;
            *)          PEER="${NET}.1" ;;
        esac
        log "link OK, ip=$MYIP peer=$PEER"
        if ping -c 2 -W 2 "$PEER" >/dev/null 2>&1; then
            msg "Link activo.\n\nEsta consola: ${MYIP%/*}\nLa otra: $PEER (responde)"
        else
            msg "Link activo.\n\nEsta consola: ${MYIP%/*}\nLa otra: $PEER (sin respuesta)\n\nActiva el link tambien alla."
        fi
    else
        log "fallo nmcli con up link"
        msg "Fallo al activar el perfil link."
        RestoreDhcp
    fi
}

# =======================================================
# Desactivar el link y volver a DHCP
# =======================================================
DeactivateLink() {
    info "Volviendo a modo router...\n\nPuede tardar unos segundos."
    RestoreDhcp
    local MYIP
    MYIP=$(CurrentIP)
    if [ -n "$MYIP" ] && [ "${MYIP#${NET}.}" = "$MYIP" ]; then
        msg "Modo router activo.\n\nIP: ${MYIP%/*}"
    else
        # Normal si el cable sigue yendo a la otra consola:
        # no hay ningun DHCP del otro lado que responda.
        log "sin IP por DHCP"
        msg "Link desactivado.\n\nSin IP: conecta el cable al router.\nSi aun asi falla, borra el perfil link."
    fi
}

# =======================================================
# Borrar el perfil por completo
# =======================================================
# Importante: se borra con nmcli, no borrando el archivo de
# /etc/NetworkManager/system-connections. Asi NetworkManager
# se entera en el momento y no hace falta reiniciar.
DeleteProfile() {
    dialog --clear --title "Borrar perfil" \
        --yesno "\nBorrar el perfil link ($(ProfileIP))?\n\nLa consola vuelve a usar solo DHCP." \
        10 $WIDTH > "$CURR_TTY" 2>&1
    [ $? -ne 0 ] && return 1

    info "Borrando perfil..."
    nmcli con down "$LINK" >/dev/null 2>&1
    nmcli con delete "$LINK" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "fallo al borrar"
        msg "No se pudo borrar el perfil."
        return 1
    fi
    RestoreDhcp
    log "perfil borrado, ip actual: $(CurrentIP)"
    msg "Perfil borrado.\n\nEl ethernet vuelve a funcionar normal,\nsin reiniciar la consola.\n\nIP: $(CurrentIP)"
}

# =======================================================
# Diagnostico en pantalla
# =======================================================
# Muestra el estado real sin necesidad de SSH. Tambien lo
# guarda en un archivo de texto que se puede leer sacando
# la SD y abriendola en la PC.
ShowDiag() {
    {
        echo "Fecha: $(date)"
        echo "Interfaz detectada: $IFACE"
        echo "Carrier (1 = cable conectado): $(cat /sys/class/net/$IFACE/carrier 2>&1)"
        echo ""
        echo "--- Direcciones ---"
        ip -4 -br addr 2>&1
        echo ""
        echo "(los nombres de redes WiFi se ocultan a proposito)"
        echo ""
        echo "--- Estado de dispositivos ---"
        nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>&1 | awk -F: '$2=="wifi" {$4="(wifi)"} 1' OFS=:
        echo ""
        echo "--- Perfiles guardados ---"
        nmcli -t -f NAME,TYPE,DEVICE con show 2>&1 | awk -F: '$2=="802-11-wireless" || $2=="wifi" {$1="(wifi)"} 1' OFS=:
        echo ""
        echo "--- Perfiles activos ---"
        nmcli -t -f NAME,TYPE,DEVICE con show --active 2>&1 | awk -F: '$2=="802-11-wireless" || $2=="wifi" {$1="(wifi)"} 1' OFS=:
        echo ""
        echo "--- Perfil link ---"
        if LinkExists; then
            nmcli con show "$LINK" 2>&1 | grep -E "connection.autoconnect:|ipv4.method:|ipv4.addresses:|connection.interface-name:"
        else
            echo "(no existe)"
        fi
        echo ""
        echo "--- Perfil DHCP ---"
        if DhcpExists; then
            echo "$DHCP: existe"
        else
            echo "$DHCP: NO EXISTE"
            echo "(por eso desactivar el link puede no devolver la red;"
            echo " usar Modo router para regenerarlo)"
        fi
    } > "$DIAG" 2>&1

    dialog --clear --title "Diagnostico (se guardo en linklan-diag.txt)" \
        --textbox "$DIAG" 20 70 > "$CURR_TTY" 2>&1
}

# =======================================================
# Menu principal
# =======================================================
MainMenu() {
    local MYIP PIP STATE CHOICE WARN
    while true; do
        MYIP=$(CurrentIP)
        [ -z "$MYIP" ] && MYIP="sin IP"

        if ! LinkExists; then
            # Todavia no hay perfil creado
            CHOICE=$(dialog --clear --no-collapse \
                --backtitle "Link LAN  |  $IFACE: $MYIP" \
                --title "Sin perfil configurado" \
                --cancel-label "Salir" \
                --menu "Esta consola no tiene perfil link.\n\nIP actual: $MYIP" \
                $HEIGHT $WIDTH 3 \
                "1" "Crear perfil de red" \
                "2" "Diagnostico" \
                "3" "Salir" \
                2>&1 > "$CURR_TTY")
            [ $? -ne 0 ] && return
            case "$CHOICE" in
                1) CreateProfile ;;
                2) ShowDiag ;;
                *) return ;;
            esac
            continue
        fi

        PIP=$(ProfileIP)
        if LinkActive; then
            STATE="ACTIVO"
        else
            STATE="inactivo"
        fi
        # Aviso si falta el perfil DHCP: sin el, el ethernet normal
        # no levanta hasta usar "Modo router".
        if DhcpExists; then
            WARN=""
        else
            WARN="\nFalta el perfil DHCP: usar Modo router."
        fi

        # Las dos opciones estan siempre visibles a proposito.
        # Modo router es la unica via para recrear el perfil DHCP,
        # y hace falta justo cuando el link NO esta activo.
        CHOICE=$(dialog --clear --no-collapse \
            --backtitle "Link LAN  |  $IFACE: $MYIP" \
            --title "Perfil link: $STATE" \
            --cancel-label "Cancelar" \
            --menu "IP de esta consola: ${PIP%/*}\nIP actual de $IFACE: ${MYIP%/*}$WARN" \
            $HEIGHT $WIDTH 5 \
            "1" "Activar link (cable entre consolas)" \
            "2" "Modo router (DHCP normal)" \
            "3" "Borrar perfil link" \
            "4" "Diagnostico" \
            "5" "Cancelar" \
            2>&1 > "$CURR_TTY")
        [ $? -ne 0 ] && return

        case "$CHOICE" in
            1) ActivateLink ;;
            2) DeactivateLink ;;
            3) DeleteProfile ;;
            4) ShowDiag ;;
            *) return ;;
        esac
    done
}

dialog --clear
MainMenu
