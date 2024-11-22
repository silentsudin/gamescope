#!/bin/sh

usage() {
    echo "Usage: $0 [--appid ID] <host>"
}

HOST=
APPID=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --appid)
            if [ "$#" -lt 2 ]; then
                echo "--appid requires a Steam application ID" >&2
                usage >&2
                exit 1
            fi
            APPID=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [ -n "$HOST" ]; then
                echo "Only one host may be specified" >&2
                usage >&2
                exit 1
            fi
            HOST=$1
            shift
            ;;
    esac
done

if [ -z "$HOST" ]; then
    usage >&2
    exit 1
fi

case "$APPID" in
    "") ;;
    0|*[!0-9]*)
        echo "Invalid Steam application ID: $APPID" >&2
        exit 1
        ;;
esac

RSYNC="rsync -rv --exclude .git --exclude venv --exclude __pycache__'"

set -e

meson build/ -Dforce_fallback_for=stb,libdisplay-info,libliftoff,wlroots,vkroots -Denable_openvr_support=false
ninja -C build/
scp build/src/gamescope "${HOST}:gamescope"
scp build/layer/libVkLayer_FROG_gamescope_wsi_x86_64.so "${HOST}:gamescope-wsi.so"

ssh "$HOST" /bin/bash -s -- "$APPID" <<'EOF'
    set -e

    appid=$1

    login_config_mounted=
    if mountpoint -q /etc/plasmalogin.conf; then
        login_config_mounted=1
    fi
    session_user=$(id -un)

    passwd_entry=$(getent passwd "$session_user") || {
        echo "Unknown remote user: $session_user" >&2
        exit 1
    }
    session_home=$(printf '%s\n' "$passwd_entry" | cut -d: -f6)
    steam_pipe="$session_home/.steam/steam.pipe"
    old_steam_pids=
    if [ -n "$appid" ]; then
        old_steam_pids=$(lsof -t "$steam_pipe" 2>/dev/null || true)
    fi

    sudo rpm-ostree usroverlay || true
    if [ -z "$login_config_mounted" ]; then
        printf '%s\n' \
            '[Autologin]' \
            'Relogin=true' \
            "User=$session_user" \
            'Session=gamemode.desktop' |
            sudo tee /run/plasmalogin.conf >/dev/null
        sudo chcon --reference=/etc/plasmalogin.conf /run/plasmalogin.conf
        sudo mount --bind /run/plasmalogin.conf /etc/plasmalogin.conf
    fi
    sudo mv ~/gamescope /usr/bin/gamescope
    sudo install -m755 ~/gamescope-wsi.so /usr/lib64/libVkLayer_FROG_gamescope_wsi_x86_64.so
    flatpak_platform_override=/run/anatase/flatpak/overrides/org.anatase.Platform/x86_64/stable
    if [ -d "$flatpak_platform_override" ]; then
        sudo install -Dm755 /usr/lib64/libVkLayer_FROG_gamescope_wsi_x86_64.so \
            "$flatpak_platform_override/lib64/libVkLayer_FROG_gamescope_wsi_x86_64.so"
    fi
    flatpak_runtime=$(readlink -f "$(flatpak info -l org.anatase.Platform 2>/dev/null || true)")
    if [ -n "$flatpak_runtime" ]; then
        flatpak_wsi="$flatpak_runtime/files/lib64/libVkLayer_FROG_gamescope_wsi_x86_64.so"
        if mountpoint -q "$flatpak_wsi"; then
            sudo umount -l "$flatpak_wsi"
        fi
        sudo mount --bind "$session_home/gamescope-wsi.so" "$flatpak_wsi"
    fi
    sudo setcap cap_sys_nice=ep /usr/bin/gamescope
    sudo systemctl stop plasmalogin
    sleep 2
    sudo systemctl start plasmalogin

    if [ -n "$appid" ]; then
        attempts=0
        while :; do
            steam_pid=$(lsof -t "$steam_pipe" 2>/dev/null | head -n 1 || true)
            if [ -n "$steam_pid" ] && ! printf '%s\n' "$old_steam_pids" | grep -Fxq "$steam_pid"; then
                break
            fi

            attempts=$((attempts + 1))
            if [ "$attempts" -ge 120 ]; then
                echo "Timed out waiting for Steam to accept launch requests" >&2
                exit 1
            fi
            sleep 0.5
        done

        game_uri="steam://rungameid/$appid"
        if ! timeout 5 sh -c 'printf "%s\n" "$1" > "$2"' sh "$game_uri" "$steam_pipe"; then
            echo "Failed to send Steam launch request for app $appid" >&2
            exit 1
        fi
        echo "Requested Steam app $appid"
    fi
EOF
