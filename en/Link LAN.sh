#!/bin/bash
# =======================================================
# Link LAN - Netplay over a direct cable between two consoles
# =======================================================
# Connects two consoles with a direct ethernet cable, with
# no router and no WiFi, using static IPs (10.9.9.1 and .2).
#
# Needs: one USB-ethernet adapter per console and a network
# cable between them.
#
# The 10.x range is used because it is the only private one
# (RFC 1918) with a two-digit first octet: 8 characters is
# the shortest possible to type on RetroArch's on-screen
# keyboard. The 9.9 avoids clashing with home networks,
# which almost always use 10.0.0.x, 10.1.1.x or 192.168.x.x.
#
# Project: r36-link-lan (MIT license)
# Gamepad handling (gptokeyb) adapted from djparent's
# dArkOSen tools (MIT).
# =======================================================

# Re-runs itself as root (nmcli needs it)
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

export TERM=linux
CURR_TTY="/dev/tty1"
LINK="link"                      # static-IP profile
DHCP="Wired connection 1"        # DHCP profile NetworkManager creates by itself
NET="10.9.9"                     # first three octets of the link
LOG="/roms/tools/linklan.log"
DIAG="/roms/tools/linklan-diag.txt"
HEIGHT="14"
WIDTH="55"

# Detects the wired interface name (eth0, enx..., etc)
IFACE=$(ls /sys/class/net/ 2>/dev/null | grep -E '^(eth|enx)' | head -1)
[ -z "$IFACE" ] && IFACE="eth0"

echo "===== $(date) =====" >> "$LOG"
log() { echo "$1" >> "$LOG"; }

chmod 666 "$CURR_TTY" 2>/dev/null
printf "\e[?25l" > "$CURR_TTY"   # hides the cursor
printf "\033[H\033[2J" > "$CURR_TTY"

# ---- Large font, readable on the 640x480 screen ----
setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz 2>/dev/null

# ---- Gamepad as keyboard, to answer the dialogs ----
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

# Cleanup on any exit path
Cleanup() {
    pkill -9 -f gptokeyb 2>/dev/null
    rm -f "$TMP_KEYS"
    setfont /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz 2>/dev/null
    printf "\e[?25h" > "$CURR_TTY"
    printf "\033[H\033[2J" > "$CURR_TTY"
}
trap Cleanup EXIT

# Box that waits for A to be pressed
msg() { dialog --clear --title "Link LAN" --msgbox "$1" 11 $WIDTH > "$CURR_TTY" 2>&1; }
# Info box with no wait (for work in progress)
info() { dialog --clear --title "Link LAN" --infobox "$1" 7 $WIDTH > "$CURR_TTY" 2>&1; }

# IP the interface actually has right now
CurrentIP() { ip -4 -br addr show "$IFACE" 2>/dev/null | awk '{print $3}'; }
# IP stored in the link profile (even while it is off)
ProfileIP() { nmcli -g ipv4.addresses con show "$LINK" 2>/dev/null; }

LinkExists() { nmcli -t -f NAME con show 2>/dev/null | grep -qx "$LINK"; }
LinkActive() { nmcli -t -f NAME con show --active 2>/dev/null | grep -qx "$LINK"; }
DhcpExists() { nmcli -t -f NAME con show 2>/dev/null | grep -qx "$DHCP"; }
# Ethernet profiles only: WiFi network names are never written
# to the log or the diagnostics (they can reveal where you live).
EthProfiles() { nmcli -t -f NAME,TYPE con show "$@" 2>/dev/null | grep ':802-3-ethernet$' | cut -d: -f1 | tr '\n' ' '; }

log "interface: $IFACE"
log "carrier: $(cat /sys/class/net/$IFACE/carrier 2>&1)"
log "ethernet profiles: $(EthProfiles)"
log "active ethernet: $(EthProfiles --active)"

# =======================================================
# Create the static-IP profile
# =======================================================
# Each console needs a different address. The menu keeps
# both of them from picking the same one by accident.
CreateProfile() {
    local CHOICE MYADDR
    CHOICE=$(dialog --clear --no-collapse \
        --backtitle "Link LAN" \
        --title "First-time setup" \
        --cancel-label "Cancel" \
        --menu "Which number does this console take?\n(the other one must take the other)" \
        11 $WIDTH 2 \
        "1" "This console will be ${NET}.1" \
        "2" "This console will be ${NET}.2" \
        2>&1 > "$CURR_TTY")

    if [ $? -ne 0 ] || [ -z "$CHOICE" ]; then
        log "creation cancelled"
        return 1
    fi

    MYADDR="${NET}.${CHOICE}/24"
    log "creating profile with $MYADDR on $IFACE"

    # never-default: keeps the console from trying to reach the
    # internet through this cable. ipv6 ignore: speeds up startup.
    nmcli con add type ethernet ifname "$IFACE" con-name "$LINK" \
        autoconnect no \
        ipv4.method manual \
        ipv4.addresses "$MYADDR" \
        ipv4.never-default yes \
        ipv6.method ignore >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        log "failed to create the profile"
        msg "Could not create the network profile."
        return 1
    fi
    msg "Profile created.\n\nThis console will be ${MYADDR%/*}\n\nRepeat on the other one with the other number."
    return 0
}

# =======================================================
# Put the interface back into normal DHCP mode
# =======================================================
# Used when deactivating the link and when deleting the profile.
# If the DHCP profile is missing (for instance because the user
# deleted it from the Wi-Fi Manager), it is recreated first.
RestoreDhcp() {
    nmcli con down "$LINK" >/dev/null 2>&1
    # Clears any static IP left stuck on the interface
    ip addr flush dev "$IFACE" 2>/dev/null
    nmcli device set "$IFACE" managed yes >/dev/null 2>&1

    # Without the DHCP profile, the only ethernet profile on the
    # system is "link", and NetworkManager brings it back up on its
    # own.
    if ! DhcpExists; then
        log "DHCP profile missing, recreating it"
        nmcli con add type ethernet ifname "$IFACE" con-name "$DHCP" \
            autoconnect yes ipv4.method auto >/dev/null 2>&1
    fi

    # Brought up by name, never with "device connect": that command
    # picks the best available profile and would re-activate "link".
    nmcli con up "$DHCP" >/dev/null 2>&1
    sleep 1
    log "after restoring DHCP: ip=$(CurrentIP) state=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^$IFACE:")"
}

# =======================================================
# Activate the link
# =======================================================
ActivateLink() {
    # NetworkManager refuses to activate a profile with no physical
    # link, so it waits for the cable to be connected first.
    ip link set "$IFACE" up 2>/dev/null
    local i CARR MYIP PEER
    for i in $(seq 1 15); do
        [ "$(cat /sys/class/net/$IFACE/carrier 2>/dev/null)" = "1" ] && break
        dialog --clear --title "Link LAN" --infobox "Waiting for the cable... ($i/15)" 7 $WIDTH > "$CURR_TTY" 2>&1
        sleep 1
    done

    CARR=$(cat /sys/class/net/$IFACE/carrier 2>/dev/null)
    log "carrier after waiting: $CARR"
    if [ "$CARR" != "1" ]; then
        log "no carrier"
        msg "No physical link.\n\nCheck the cable, the adapters,\nand that the other console is powered on."
        return 1
    fi

    info "Activating link..."
    nmcli con down "$DHCP" >/dev/null 2>&1
    if nmcli con up "$LINK" >/dev/null 2>&1; then
        MYIP=$(CurrentIP)
        # Works out the other console's address from its own
        case "$MYIP" in
            ${NET}.1/*) PEER="${NET}.2" ;;
            *)          PEER="${NET}.1" ;;
        esac
        log "link OK, ip=$MYIP peer=$PEER"
        if ping -c 2 -W 2 "$PEER" >/dev/null 2>&1; then
            msg "Link active.\n\nThis console: ${MYIP%/*}\nThe other one: $PEER (responding)"
        else
            msg "Link active.\n\nThis console: ${MYIP%/*}\nThe other one: $PEER (no response)\n\nActivate the link there too."
        fi
    else
        log "nmcli con up link failed"
        msg "Failed to activate the link profile."
        RestoreDhcp
    fi
}

# =======================================================
# Deactivate the link and go back to DHCP
# =======================================================
DeactivateLink() {
    info "Switching back to router mode...\n\nThis may take a few seconds."
    RestoreDhcp
    local MYIP
    MYIP=$(CurrentIP)
    if [ -n "$MYIP" ] && [ "${MYIP#${NET}.}" = "$MYIP" ]; then
        msg "Router mode active.\n\nIP: ${MYIP%/*}"
    else
        # Normal if the cable still goes to the other console:
        # there is no DHCP server on the other end to answer.
        log "no IP from DHCP"
        msg "Link deactivated.\n\nNo IP: connect the cable to a router.\nIf it still fails, delete the link profile."
    fi
}

# =======================================================
# Delete the profile entirely
# =======================================================
# Important: deleted with nmcli, not by removing the file in
# /etc/NetworkManager/system-connections. That way NetworkManager
# finds out right away and no reboot is needed.
DeleteProfile() {
    dialog --clear --title "Delete profile" \
        --yesno "\nDelete the link profile ($(ProfileIP))?\n\nThe console goes back to plain DHCP." \
        10 $WIDTH > "$CURR_TTY" 2>&1
    [ $? -ne 0 ] && return 1

    info "Deleting profile..."
    nmcli con down "$LINK" >/dev/null 2>&1
    nmcli con delete "$LINK" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "failed to delete"
        msg "Could not delete the profile."
        return 1
    fi
    RestoreDhcp
    log "profile deleted, current ip: $(CurrentIP)"
    msg "Profile deleted.\n\nEthernet works normally again,\nwithout rebooting the console.\n\nIP: $(CurrentIP)"
}

# =======================================================
# On-screen diagnostics
# =======================================================
# Shows the real state without needing SSH. It is also saved
# to a text file that can be read by pulling the SD card and
# opening it on a PC.
ShowDiag() {
    {
        echo "Date: $(date)"
        echo "Detected interface: $IFACE"
        echo "Carrier (1 = cable connected): $(cat /sys/class/net/$IFACE/carrier 2>&1)"
        echo ""
        echo "--- Addresses ---"
        ip -4 -br addr 2>&1
        echo ""
        echo "(WiFi network names are hidden on purpose)"
        echo ""
        echo "--- Device status ---"
        nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>&1 | awk -F: '$2=="wifi" {$4="(wifi)"} 1' OFS=:
        echo ""
        echo "--- Saved profiles ---"
        nmcli -t -f NAME,TYPE,DEVICE con show 2>&1 | awk -F: '$2=="802-11-wireless" || $2=="wifi" {$1="(wifi)"} 1' OFS=:
        echo ""
        echo "--- Active profiles ---"
        nmcli -t -f NAME,TYPE,DEVICE con show --active 2>&1 | awk -F: '$2=="802-11-wireless" || $2=="wifi" {$1="(wifi)"} 1' OFS=:
        echo ""
        echo "--- Link profile ---"
        if LinkExists; then
            nmcli con show "$LINK" 2>&1 | grep -E "connection.autoconnect:|ipv4.method:|ipv4.addresses:|connection.interface-name:"
        else
            echo "(does not exist)"
        fi
        echo ""
        echo "--- DHCP profile ---"
        if DhcpExists; then
            echo "$DHCP: exists"
        else
            echo "$DHCP: MISSING"
            echo "(use Router mode to recreate it)"
        fi
    } > "$DIAG" 2>&1

    dialog --clear --title "Diagnostics (saved to linklan-diag.txt)" \
        --textbox "$DIAG" 20 70 > "$CURR_TTY" 2>&1
}

# =======================================================
# Main menu
# =======================================================
MainMenu() {
    local MYIP PIP STATE CHOICE WARN
    while true; do
        MYIP=$(CurrentIP)
        [ -z "$MYIP" ] && MYIP="no IP"

        if ! LinkExists; then
            # No profile created yet
            CHOICE=$(dialog --clear --no-collapse \
                --backtitle "Link LAN  |  $IFACE: $MYIP" \
                --title "No profile configured" \
                --cancel-label "Exit" \
                --menu "This console has no link profile.\n\nCurrent IP: $MYIP" \
                $HEIGHT $WIDTH 3 \
                "1" "Create network profile" \
                "2" "Diagnostics" \
                "3" "Exit" \
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
            STATE="ACTIVE"
        else
            STATE="inactive"
        fi
        # Warns if the DHCP profile is missing: without it, normal
        # ethernet will not come up until Router mode is used.
        if DhcpExists; then
            WARN=""
        else
            WARN="\nDHCP profile missing: use Router mode."
        fi

        # Both options are always visible on purpose. Router mode is
        # the only way to recreate the DHCP profile, and it is needed
        # exactly when the link is NOT active.
        CHOICE=$(dialog --clear --no-collapse \
            --backtitle "Link LAN  |  $IFACE: $MYIP" \
            --title "Link profile: $STATE" \
            --cancel-label "Cancel" \
            --menu "This console's IP: ${PIP%/*}\nCurrent IP of $IFACE: ${MYIP%/*}$WARN" \
            $HEIGHT $WIDTH 5 \
            "1" "Activate link (cable between consoles)" \
            "2" "Router mode (normal DHCP)" \
            "3" "Delete link profile" \
            "4" "Diagnostics" \
            "5" "Cancel" \
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
