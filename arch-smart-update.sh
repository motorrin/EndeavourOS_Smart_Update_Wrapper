#!/bin/bash

# --- 1.1 Color Palette ---
if [ -t 1 ]; then
    reset='\033[0m'
    bold='\033[1m'
    dim='\033[2m'
    red='\033[38;5;196m'
    green='\033[38;5;71m'
    yellow='\033[38;5;214m'
    blue='\033[38;5;75m'
    magenta='\033[38;5;176m'
    cyan='\033[38;5;79m'
    white='\033[38;5;255m'
    gray='\033[38;5;244m'
    bg_crit='\033[48;5;160;38;5;255;1m'
    bg_core='\033[48;5;237;38;5;214;1m'
    bg_nuke='\033[48;5;196;38;5;255;1m'
    bg_feat='\033[48;5;214;38;5;0;1m'
else
    reset='' bold='' dim='' red='' green='' yellow='' blue=''
    magenta='' cyan='' white='' gray='' bg_crit='' bg_core='' bg_nuke='' bg_feat=''
fi

# --- 1.2 Dependency Check ---
for cmd in python3 tar awk stat fuser curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${red}Error: Required command '$cmd' is not installed.${reset}"
        if [[ "$cmd" == "fuser" ]]; then
            echo -e "${gray}Please install the 'psmisc' package: sudo pacman -S psmisc${reset}"
        fi
        exit 1
    fi
done

# --- 1.3 Daemon mode ---
DAEMON_MODE=false
if [[ "$1" == "--daemon" || "$1" == "--check" ]]; then
    DAEMON_MODE=true
fi

# --- 1.4 Helper: Prompt ---
prompt_with_timeout() {
    local msg="$1" options="$2" timeout_sec="$3" var_name="$4"
    local user_input=""
    if ! $DAEMON_MODE; then
        for (( i=timeout_sec; i>0; i-- )); do
            echo -ne "\r\033[2K  ${white}${msg}[${options}] (${i}s): ${reset}"
            if read -t 1 -n 1 -r user_input </dev/tty 2>/dev/null; then break; else (( $? != 142 )) && break; fi
        done
        echo ""
    fi
    [[ -n "$user_input" ]] && declare -g "$var_name=$user_input"
}

# --- 2. Configuration & External Files ---
if [[ -n "$SUDO_USER" ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME=$HOME
fi
CONFIG_DIR="${XDG_CONFIG_HOME:-$USER_HOME/.config}/arch-smart-update"
mkdir -p "$CONFIG_DIR"

PKG_CONF="$CONFIG_DIR/packages.conf"
SETTINGS_DEFAULT="$CONFIG_DIR/settings.default.conf"
SETTINGS_CONF="$CONFIG_DIR/settings.conf"
DAEMON_TEMPLATE="$CONFIG_DIR/daemon.template"

update_from_github() {
    local file_path="$1"
    local url="$2"
    local expected_string="$3"
    local filename=$(basename "$file_path")
    local tmp_file
    tmp_file=$(mktemp "/tmp/${filename}.XXXXXX")

    if curl -sLfo "$tmp_file" --connect-timeout 5 --max-time 10 "$url"; then
        if [[ -n "$expected_string" ]] && ! grep -q "$expected_string" "$tmp_file"; then
            rm -f "$tmp_file"
            [[ ! -f "$file_path" ]] && echo -e "${red}Failed to download $filename (Invalid format / Captive Portal)${reset}"
            return 1
        fi

        if [[ "$filename" == "settings.default.conf" ]]; then
            if awk '/^CUSTOM_CMDS=\(/ {in_block=1; next} in_block && /^\)/ {in_block=0} in_block && /^[[:space:]]*[^#[:space:]]/ {print "DANGER"; exit}' "$tmp_file" | grep -q "DANGER"; then
                rm -f "$tmp_file"
                [[ ! -f "$file_path" ]] && echo -e "${red}Security Alert: Active custom commands detected in default settings. Download rejected!${reset}"
                return 1
            fi
        fi

        if [[ ! -f "$file_path" ]]; then
            mv "$tmp_file" "$file_path"
            echo -e "${dim}Downloaded $filename from GitHub...${reset}"
        elif ! cmp -s "$file_path" "$tmp_file"; then
            mv "$tmp_file" "$file_path"
            echo -e "${green}Updated $filename from GitHub!${reset}"
        else
            rm -f "$tmp_file"
        fi
    else
        [[ ! -f "$file_path" ]] && echo -e "${red}Failed to download $filename (No internet connection?)${reset}"
        rm -f "$tmp_file"
    fi
}

validate_user_conf() {
    local file="$1"
    local label="$2"

    [[ ! -f "$file" ]] && return 0

    local owner
    owner=$(stat -Lc '%U' "$file" 2>/dev/null)
    local real_user="${SUDO_USER:-$(id -un)}"
    if [[ "$owner" != "$real_user" && "$owner" != "root" ]]; then
        echo -e "${bg_nuke}SECURITY ${reset} ${red}$label is owned by '${owner:-UNKNOWN}', expected '$real_user' or 'root'. Refusing to load.${reset}"
        return 1
    fi

    local perms
    perms=$(stat -Lc '%a' "$file" 2>/dev/null)
    if (( 8#${perms:-0} & 8#022 )); then
        echo -e "${bg_nuke}SECURITY ${reset} ${red}$label is group/world-writable (${perms}). Refusing to load.${reset}"
        echo -e "${yellow}Fix with: chmod 600 \"$file\"${reset}"
        return 1
    fi
    return 0
}

parse_bash_array() {
    local file=$1
    local arr_name=$2
    awk -v var="$arr_name" '
        BEGIN { in_arr=0 }
        { gsub(/#.*/, "") }
        $0 ~ "^"var"(\\+)?=\\s*\\(" { in_arr=1; sub(/^.*\(/, "") }
        in_arr {
            while (match($0, /"[^"]*"|\047[^\047]*\047/)) {
                print substr($0, RSTART+1, RLENGTH-2)
                $0 = substr($0, RSTART+RLENGTH)
            }
            if ($0 ~ /\)/) in_arr=0
        }
    ' "$file"
}

migrate_old_configs() {
    local migrated=false
    local old_set="$CONFIG_DIR/other_settings.conf"
    local old_ref="$CONFIG_DIR/reflector.conf"
    local old_cmd="$CONFIG_DIR/custom_commands.conf"
    local old_pkg="$CONFIG_DIR/user_packages.conf"

    [[ ! -f "$old_set" && ! -f "$old_ref" && ! -f "$old_cmd" && ! -f "$old_pkg" ]] && return 1

    echo -e "${dim}Migrating old configuration files to settings.conf...${reset}"

    if [[ -f "$old_set" ]]; then
        while IFS='=' read -r key val; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            val="${val//[\"\'$'\r']/}"
            sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$SETTINGS_CONF"
        done < "$old_set"
        migrated=true
    fi

    if [[ -f "$old_ref" ]]; then
        local ref_cmd=$(grep -v '^#' "$old_ref" | grep '[^[:space:]]' | head -n 1)
        if [[ -n "$ref_cmd" ]]; then
            local esc_ref=$(printf '%s\n' "$ref_cmd" | sed -e 's/[\/&]/\\&/g')
            sed -i "s|^# CUSTOM_REFLECTOR_CMD=.*|CUSTOM_REFLECTOR_CMD=\"${esc_ref}\"|" "$SETTINGS_CONF"
        fi
        migrated=true
    fi

    if [[ -f "$old_cmd" ]]; then
        local cmds=""
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -z "$line" || "$line" == \#* ]] && continue
            cmds+="    \"${line//\"/\\\"}\"\n"
        done < "$old_cmd"

        if [[ -n "$cmds" ]]; then
            awk -v inject="$cmds" '
                /^CUSTOM_CMDS=\(/ { print; printf "%s", inject; in_block=1; next }
                in_block && /^\)/ { print; in_block=0; next }
                in_block { next }
                { print }
            ' "$SETTINGS_CONF" > "${SETTINGS_CONF}.tmp" && mv "${SETTINGS_CONF}.tmp" "$SETTINGS_CONF"
        fi
        migrated=true
    fi

    if [[ -f "$old_pkg" ]]; then
        for cat in NUCLEAR_PKGS CRITICAL_PKGS FEATURE_PKGS; do
            local items=$(parse_bash_array "$old_pkg" "$cat" | sed 's/^/    "/; s/$/"/')
            if [[ -n "$items" ]]; then
                awk -v arr="USER_${cat}" -v inject="$items" '
                    $0 ~ "^"arr"=\\(" { print; print inject; in_block=1; next }
                    in_block && /^\)/ { print; in_block=0; next }
                    in_block { next }
                    { print }
                ' "$SETTINGS_CONF" > "${SETTINGS_CONF}.tmp" && mv "${SETTINGS_CONF}.tmp" "$SETTINGS_CONF"
            fi
        done
        migrated=true
    fi

    if $migrated; then
        echo -e "  ${green}Migration complete. Removing old configuration files.${reset}"
        rm -f "$old_set" "$old_ref" "$old_cmd" "$old_pkg" \
              "$CONFIG_DIR/other_settings.default.conf" \
              "$CONFIG_DIR/reflector.default.conf" \
              "$CONFIG_DIR/custom_commands.default.conf"
        return 0
    fi
    return 1
}

echo -e "${dim}Checking for configuration updates...${reset}"

update_from_github "$PKG_CONF" "https://raw.githubusercontent.com/motorrin/Arch_Smart_Update/main/packages.conf" "NUCLEAR_PKGS"
update_from_github "$SETTINGS_DEFAULT" "https://raw.githubusercontent.com/motorrin/Arch_Smart_Update/main/settings.conf" "PROMPT_MIRROR_REFRESH"
update_from_github "$DAEMON_TEMPLATE" "https://raw.githubusercontent.com/motorrin/Arch_Smart_Update/main/daemon.template" "[TimerTemplate]"

if [[ ! -f "$SETTINGS_CONF" && -f "$SETTINGS_DEFAULT" ]]; then
    cp "$SETTINGS_DEFAULT" "$SETTINGS_CONF"
    chmod 600 "$SETTINGS_CONF"
    echo -e "${dim}Created default $SETTINGS_CONF${reset}"

    if ! migrate_old_configs; then
        echo -e "\n${blue}${bold}[First Run Setup]${reset}"
        setup_ans="Y"
        daemon_ans="N"

        prompt_with_timeout "Allow mirror ranking option before update (with confirmation)?" "Y/n" 15 setup_ans
        prompt_with_timeout "Enable background update checker?" "y/N" 15 daemon_ans

        echo ""

        if [[ "$setup_ans" =~ ^[Nn]$ ]]; then
            sed -i 's/^PROMPT_MIRROR_REFRESH=.*/PROMPT_MIRROR_REFRESH=false/' "$SETTINGS_CONF"
            echo -e "  ${dim}Mirror ranking prompt disabled.${reset}"
        else
            sed -i 's/^PROMPT_MIRROR_REFRESH=.*/PROMPT_MIRROR_REFRESH=true/' "$SETTINGS_CONF"
            echo -e "  ${dim}Mirror ranking prompt enabled.${reset}"
        fi

        if [[ "$daemon_ans" =~ ^[Yy]$ ]]; then
            sed -i 's/^ENABLE_BACKGROUND_CHECK=.*/ENABLE_BACKGROUND_CHECK=true/' "$SETTINGS_CONF"
            echo -e "  ${dim}Background checker enabled.${reset}"
            if ! pacman -Q libnotify >/dev/null 2>&1; then
                echo -e "  ${yellow}Warning: The ${red}libnotify${yellow} package is not installed. Please install it for notifications to work.${reset}\n"
            else
                echo ""
            fi
        else
            sed -i 's/^ENABLE_BACKGROUND_CHECK=.*/ENABLE_BACKGROUND_CHECK=false/' "$SETTINGS_CONF"
            echo -e "  ${dim}Background checker disabled.${reset}\n"
        fi
    fi
else
    migrate_old_configs
fi

if ! validate_user_conf "$SETTINGS_CONF" "settings.conf"; then
    echo -e "${yellow}Settings disabled due to security check failure.${reset}"
    SETTINGS_CONF=""
fi

if ! validate_user_conf "$PKG_CONF" "packages.conf"; then
    echo -e "${yellow}Packages config disabled due to security check failure.${reset}"
    PKG_CONF=""
fi

NUCLEAR_PKGS=("glibc" "linux" "systemd" "pacman" "nvidia" "mkinitcpio")
CRITICAL_PKGS=("base" "base-devel" "mesa" "wayland" "xorg-server" "dbus")
FEATURE_PKGS=("pipewire" "plasma-desktop" "gnome-shell" "hyprland" "networkmanager")
CUSTOM_CMDS=()

if [[ -f "$PKG_CONF" ]]; then
    NUCLEAR_PKGS=($(parse_bash_array "$PKG_CONF" "NUCLEAR_PKGS"))
    CRITICAL_PKGS=($(parse_bash_array "$PKG_CONF" "CRITICAL_PKGS"))
    FEATURE_PKGS=($(parse_bash_array "$PKG_CONF" "FEATURE_PKGS"))
else
    echo -e "${red}Could not load packages.conf. Using built-in basic fallbacks.${reset}"
fi

if [[ -n "$SETTINGS_CONF" && -f "$SETTINGS_CONF" ]]; then
    while IFS='=' read -r key val; do
        val="${val//[\"\'$'\r']/}"
        case "$key" in
            AUR_HELPER_OVERRIDE|PROMPT_MIRROR_REFRESH|MAX_BACKUP_COPIES|CHECK_INTERVAL|START_DELAY|ENABLE_BACKGROUND_CHECK|T_MIRROR_H|T_FEAT_H|T_CRIT_H|T_DE_H|T_NUKE_H|IGNORE_PATCH_TIMERS|GENERATE_LOGS|MAX_LOG_NUMBERS|CUSTOM_REFLECTOR_CMD)
                declare -g "$key=$val" ;;
        esac
    done < "$SETTINGS_CONF"

    mapfile -t USER_NUKE < <(parse_bash_array "$SETTINGS_CONF" "USER_NUCLEAR_PKGS")
    [[ ${#USER_NUKE[@]} -gt 0 ]] && NUCLEAR_PKGS+=("${USER_NUKE[@]}")

    mapfile -t USER_CRIT < <(parse_bash_array "$SETTINGS_CONF" "USER_CRITICAL_PKGS")
    [[ ${#USER_CRIT[@]} -gt 0 ]] && CRITICAL_PKGS+=("${USER_CRIT[@]}")

    mapfile -t USER_FEAT < <(parse_bash_array "$SETTINGS_CONF" "USER_FEATURE_PKGS")
    [[ ${#USER_FEAT[@]} -gt 0 ]] && FEATURE_PKGS+=("${USER_FEAT[@]}")

    mapfile -t CUSTOM_CMDS < <(parse_bash_array "$SETTINGS_CONF" "CUSTOM_CMDS")

    [[ "$T_MIRROR_H" =~ ^[0-9]+$ ]] || T_MIRROR_H=3
    [[ "$T_FEAT_H" =~ ^[0-9]+$ ]] || T_FEAT_H=6
    [[ "$T_CRIT_H" =~ ^[0-9]+$ ]] || T_CRIT_H=12
    [[ "$T_DE_H" =~ ^[0-9]+$ ]] || T_DE_H=12
    [[ "$T_NUKE_H" =~ ^[0-9]+$ ]] || T_NUKE_H=24
fi

: ${ENABLE_BACKGROUND_CHECK:=false}
: ${CHECK_INTERVAL:=30min}
: ${START_DELAY:=5min}
: ${GENERATE_LOGS:=false}
: ${MAX_LOG_NUMBERS:=5}
: ${T_MIRROR_H:=3}
: ${T_FEAT_H:=6}
: ${T_CRIT_H:=12}
: ${T_DE_H:=12}
: ${T_NUKE_H:=24}
: ${IGNORE_PATCH_TIMERS:=true}

declare -A NUKE_MAP
for pkg in "${NUCLEAR_PKGS[@]}"; do NUKE_MAP["$pkg"]=1; done

declare -A CRIT_MAP
for pkg in "${CRITICAL_PKGS[@]}"; do CRIT_MAP["$pkg"]=1; done

declare -A FEAT_MAP
for pkg in "${FEATURE_PKGS[@]}"; do FEAT_MAP["$pkg"]=1; done

sync_daemon_state() {
    [[ "$DAEMON_MODE" == true ]] && return 0

    local SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$USER_HOME/.config}/systemd/user"

    if [[ "${ENABLE_BACKGROUND_CHECK,,}" == "true" ]]; then
        if ! command -v fakeroot >/dev/null 2>&1; then
            echo -e "${yellow}Background check requires 'fakeroot' (install base-devel). Disabling daemon.${reset}"
            ENABLE_BACKGROUND_CHECK="false"
            if systemctl --user is-active --quiet arch-smart-update.timer 2>/dev/null || [[ -f "$SYSTEMD_USER_DIR/arch-smart-update.timer" ]]; then
                systemctl --user disable --now arch-smart-update.timer >/dev/null 2>&1
                rm -f "$SYSTEMD_USER_DIR/arch-smart-update.service" "$SYSTEMD_USER_DIR/arch-smart-update.timer"
                systemctl --user daemon-reload >/dev/null 2>&1
            fi
            return 0
        fi
        mkdir -p "$SYSTEMD_USER_DIR"

        if [[ -f "$DAEMON_TEMPLATE" ]]; then
            local SCRIPT_PATH=$(realpath "$(command -v "$0" || echo "$0")")
            local TMP_SVC=$(mktemp) TMP_TMR=$(mktemp)

            awk -v script="$SCRIPT_PATH" -v delay="$START_DELAY" -v interval="$CHECK_INTERVAL" -v svc="$TMP_SVC" -v tmr="$TMP_TMR" '
                /^\[TimerTemplate\]/ { in_timer=1; next }
                {
                    gsub(/__SCRIPT_PATH__/, "\"" script "\"")
                    gsub(/__START_DELAY__/, delay)
                    gsub(/__CHECK_INTERVAL__/, interval)

                    if (in_timer) print > tmr
                    else print > svc
                }
            ' "$DAEMON_TEMPLATE"

            if ! cmp -s "$TMP_SVC" "$SYSTEMD_USER_DIR/arch-smart-update.service" || ! cmp -s "$TMP_TMR" "$SYSTEMD_USER_DIR/arch-smart-update.timer"; then
                mv "$TMP_SVC" "$SYSTEMD_USER_DIR/arch-smart-update.service"
                mv "$TMP_TMR" "$SYSTEMD_USER_DIR/arch-smart-update.timer"
                chmod 644 "$SYSTEMD_USER_DIR/arch-smart-update.service" "$SYSTEMD_USER_DIR/arch-smart-update.timer"
                systemctl --user daemon-reload >/dev/null 2>&1
                systemctl --user enable --now arch-smart-update.timer >/dev/null 2>&1
            else
                rm -f "$TMP_SVC" "$TMP_TMR"
            fi
        fi
    else
        if systemctl --user is-active --quiet arch-smart-update.timer 2>/dev/null || [[ -f "$SYSTEMD_USER_DIR/arch-smart-update.timer" ]]; then
            systemctl --user disable --now arch-smart-update.timer >/dev/null 2>&1
            rm -f "$SYSTEMD_USER_DIR/arch-smart-update.service" "$SYSTEMD_USER_DIR/arch-smart-update.timer"
            systemctl --user daemon-reload >/dev/null 2>&1
        fi
    fi
}

sync_daemon_state

if [[ "${GENERATE_LOGS,,}" == "true" ]]; then
    LOG_DIR="$CONFIG_DIR/logs"
    mkdir -p "$LOG_DIR"

    latest_log=$(ls -1 "$LOG_DIR"/log_* 2>/dev/null | grep -E 'log_[0-9]+$' | sort -V | tail -n 1)
    if [[ -z "$latest_log" ]]; then
        next_num=1
    else
        latest_num="${latest_log##*_}"
        next_num=$(( 10#$latest_num + 1 ))
    fi

    printf -v log_name "log_%06d" "$next_num"
    LOG_FILE="$LOG_DIR/$log_name"

    echo "=======================================================================" > "$LOG_FILE"
    echo "Arch Smart Update Log" >> "$LOG_FILE"
    echo "Time: $(date +'%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "Mode: $(if $DAEMON_MODE; then echo "Daemon (Background)"; else echo "Interactive"; fi)" >> "$LOG_FILE"
    echo "=======================================================================" >> "$LOG_FILE"

    if $DAEMON_MODE; then
        exec >> "$LOG_FILE" 2>&1
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    existing_logs=( $(ls -1 "$LOG_DIR"/log_[0-9][0-9][0-9][0-9][0-9][0-9] 2>/dev/null | sort -V) )
    if (( ${#existing_logs[@]} > MAX_LOG_NUMBERS )); then
        remove_count=$(( ${#existing_logs[@]} - MAX_LOG_NUMBERS ))
        for (( i=0; i<remove_count; i++ )); do
            rm -f "${existing_logs[$i]}"
        done
    fi
fi

# --- 3. Temporary Files ---
OUTPUT_FILE=$(mktemp)
SYNC_LOG=$(mktemp)
REFL_LOG=$(mktemp)

if ! CHECK_DB=$(mktemp -d /tmp/checkupdates-db.XXXXXX); then
    echo -e "${red}Error: Could not create temp db directory.${reset}"
    exit 1
fi

cleanup() {
    if [[ -n "${SUDO_KEEP_ALIVE_PID:-}" ]] && kill -0 "$SUDO_KEEP_ALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null
    fi

    if [[ -n "$CHECK_DB" && -d "$CHECK_DB" && "$CHECK_DB" == /tmp/* && "$CHECK_DB" != "/tmp/" ]]; then
        rm -rf "$CHECK_DB" 2>/dev/null

        if [[ -d "$CHECK_DB" ]]; then
            sudo -n rm -rf -- "$CHECK_DB" 2>/dev/null

            if [[ -d "$CHECK_DB" ]]; then
                echo -e "\n\r\033[2K${yellow}Cleaning up temporary RAM files (/tmp)... Password required.${reset}"
                sudo rm -rf -- "$CHECK_DB"
            fi
        fi
    fi

    local files_to_remove=()
    [[ -f "$OUTPUT_FILE" ]] && files_to_remove+=("$OUTPUT_FILE")
    [[ -f "$SYNC_LOG" ]] && files_to_remove+=("$SYNC_LOG")
    [[ -f "$REFL_LOG" ]] && files_to_remove+=("$REFL_LOG")

    if [[ ${#files_to_remove[@]} -gt 0 ]]; then
        rm -f "${files_to_remove[@]}"
    fi
}

trap cleanup EXIT INT TERM

# --- 4. Helper Functions ---
log_step() {
    echo -e "${dim}[$(date +%T)] $1${reset}"
}

get_update_type() {
    local old=$1
    local new=$2
    local level=${3:-3}

    local v_old=${old#*:}
    local v_new=${new#*:}

    if [[ "$v_new" == "latest-commit" ]]; then
        echo "MINOR"
        return
    fi

    if [[ "$old" == *":"* || "$new" == *":"* ]]; then
        local e_old=${old%%:*}
        local e_new=${new%%:*}
        [[ "$e_old" != "$e_new" ]] && { echo "EPOCH"; return; }
    fi

    local up_old="${v_old%-*}"
    local up_new="${v_new%-*}"

    local nums_old=($(echo "$up_old" | sed 's/[^0-9]/ /g'))
    local nums_new=($(echo "$up_new" | sed 's/[^0-9]/ /g'))

    local len=${#nums_new[@]}
    for (( i=0; i<len; i++ )); do
        local n_old=${nums_old[$i]}
        local n_new=${nums_new[$i]}

        [[ -z "$n_old" ]] && { echo "MINOR"; return; }

        if (( 10#${n_old:-0} != 10#${n_new:-0} )); then
            if (( (10#${n_new:-0} >= 2020 && 10#${n_new:-0} <= 2100) || \
                  (10#${n_new:-0} >= 20200000 && 10#${n_new:-0} <= 21001231) )); then
                echo "CALVER"
                return
            fi

            if (( i == 0 )); then
                echo "MAJOR"
                return
            elif (( i == 1 )); then
                echo "MINOR"
                return
            else
                if (( level == 0 )); then
                    echo "MINOR"
                else
                    echo "Patch"
                fi
                return
            fi
        fi
    done

    echo "Patch"
}

get_type_color() {
    case $1 in
        "MAJOR") echo "$red$bold" ;;
        "CALVER") echo "$blue$bold" ;;
        "MINOR") echo "$cyan" ;;
        "EPOCH") echo "$magenta" ;;
        *) echo "$gray" ;;
    esac
}

check_arch_news() {
    log_step "Starting Arch News check (Python)..."
    echo -ne "${gray}Checking Arch News... ${reset}"

    if news_ts=$(python3 -c "
import sys, urllib.request, xml.etree.ElementTree as ET, email.utils
try:
    req = urllib.request.Request('https://archlinux.org/feeds/news/', headers={'User-Agent': 'ArchSmartUpdate/1.0'})
    with urllib.request.urlopen(req, timeout=5) as resp:
        root = ET.fromstring(resp.read())
    item = root.find('./channel/item')
    if item is not None:
        pubDate = item.find('pubDate').text
        parsed = email.utils.parsedate_tz(pubDate)
        print(int(email.utils.mktime_tz(parsed)))
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
"); then
        now_time=$(date +%s)
        diff_hours=$(( (now_time - news_ts) / 3600 ))

        if (( diff_hours < 336 )); then # 14 days
            echo -e "\r\033[2K${red}${bold}WARNING: Fresh Arch News detected ($diff_hours h ago)!${reset}"
            echo -e "  ${red}Check https://archlinux.org/ before updating.${reset}\n"

            if [[ "$DAEMON_MODE" == true ]]; then
                NEWS_CACHE="${XDG_RUNTIME_DIR:-/tmp}/arch-smart-update-news-cache-${USER:-$(id -un)}"
                OLD_NEWS_TS=0
                [[ -f "$NEWS_CACHE" ]] && OLD_NEWS_TS=$(cat "$NEWS_CACHE" 2>/dev/null)

                if (( news_ts != OLD_NEWS_TS )); then
                    if command -v notify-send >/dev/null 2>&1; then
                        notify-send -a "Arch Smart Update" -u critical -i dialog-warning \
                            "Attention: Arch News detected ($diff_hours h. ago)!\nCheck archlinux.org."
                    fi
                    echo "$news_ts" > "$NEWS_CACHE"
                fi
            fi
        else
            echo -e "\r\033[2K${green}No fresh Arch News (last: ${diff_hours}h ago).${reset}\n"
        fi
    else
        echo -e "\r\033[2K${dim}Could not check Arch News (Connection or XML error).${reset}\n"
    fi
}

backup_pacman_db() {
    local BACKUP_DIR="/var/lib/pacman/backup"
    local KEEP_COPIES=${MAX_BACKUP_COPIES:-5}

    log_step "Creating Pacman DB backup..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        sudo mkdir -p "$BACKUP_DIR"
    fi

    local BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
    local BACKUP_FILE="$BACKUP_DIR/pacman_database_$BACKUP_DATE.tar.gz"

    if sudo tar --xattrs --warning=no-file-changed -czf "$BACKUP_FILE" -C /var/lib/pacman/ local; then
        echo -e "  ${green}Backup created: ${white}$(basename "$BACKUP_FILE")${reset}"

        (cd "$BACKUP_DIR" && ls -tp pacman_database_*.tar.gz | grep -v '/$' | tail -n +$((KEEP_COPIES + 1)) | xargs -I {} sudo rm -- {})
    else
        echo -e "  ${red}Failed to create backup!${reset}"
        echo -ne "  ${yellow}Continue anyway? [y/N]: ${reset}"
        read -r cont
        if [[ ! "$cont" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# --- 5. Mirror Refresh Function ---
get_current_mirror() {
    local mirror
    mirror=$(awk -F/ '/^Server[ \t]*=/ {print $3; exit}' /etc/pacman.d/mirrorlist 2>/dev/null)
    echo "${mirror:-Unknown}"
}

refresh_mirrors() {
    if [[ "$DAEMON_MODE" == true ]]; then
        return 1
    fi
    local reason="${1:-Mirror instability detected (timeouts or errors).}"

    local mirror_list="/etc/pacman.d/mirrorlist"
    local current_mirror=$(get_current_mirror)
    local mirror_age="Unknown"

    if [[ -f "$mirror_list" ]]; then
        local file_ts=$(stat -c %Y "$mirror_list" 2>/dev/null)
        if [[ -n "$file_ts" ]]; then
            local now_ts=$(date +%s)
            local diff_sec=$((now_ts - file_ts))

            if (( diff_sec < 0 )); then
                mirror_age="just now"
            else
                local diff_days=$((diff_sec / 86400))
                local diff_hours=$(( (diff_sec % 86400) / 3600 ))
                local diff_mins=$(( (diff_sec % 3600) / 60 ))
                if (( diff_days > 0 )); then
                    mirror_age="${diff_days}d ${diff_hours}h ago"
                elif (( diff_hours > 0 )); then
                    mirror_age="${diff_hours}h ${diff_mins}m ago"
                else
                    mirror_age="${diff_mins}m ago"
                fi
            fi
        fi
    fi

    local CUSTOM_REFLECTOR="${CUSTOM_REFLECTOR_CMD:-}"
    local DEFAULT_REFLECTOR="sudo reflector --country Germany,Netherlands,France,Norway --protocol https --age 12 --latest 50 --number 20 --sort rate --save /etc/pacman.d/mirrorlist --download-timeout 10"
    local ACTUAL_CMD="${CUSTOM_REFLECTOR:-$DEFAULT_REFLECTOR}"

    echo -e "\n${yellow}${bold}!  $reason${reset}"
    echo -e "  ${dim}Current mirror: ${white}$current_mirror${dim} (Last ranked: $mirror_age)${reset}"
    echo -e "  ${dim}Command: ${white}$ACTUAL_CMD${reset}"
    echo -e "  ${dim}Can be changed in the reflector.conf file.${reset}"
    echo -ne "  ${white}Refresh mirrors now? [Y/n]: ${reset}"
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ || -z "$ans" ]]; then

        if command -v eos-rankmirrors &>/dev/null; then
            echo -e "  ${blue}Ranking EndeavourOS mirrors (Timeout: 5s)...${reset}"
            if sudo eos-rankmirrors -t 5 > /dev/null; then
                echo -e "  ${green}EndeavourOS mirrors updated.${reset}"
            else
                echo -e "  ${red}Failed to rank EOS mirrors.${reset}"
            fi
        fi

        if command -v cachyos-rate-mirrors &>/dev/null; then
            echo -e "  ${blue}Ranking CachyOS mirrors...${reset}"
            if sudo cachyos-rate-mirrors; then
                echo -e "  ${green}CachyOS mirrors updated.${reset}"
            else
                echo -e "  ${red}Failed to rank CachyOS mirrors.${reset}"
            fi
        fi

        if command -v reflector &>/dev/null; then
            echo -e "\n  ${blue}Running reflector for Arch Linux...${reset}"

            local REFL_SUCCESS=false

            run_refl_and_check() {
                local cmd="$1"

                bash -c "$cmd" 2>&1 | tee "$REFL_LOG"
                local exit_code=${PIPESTATUS[0]}

                local err_count
                err_count=$(grep -cEi "warning: failed to rate|timed out|error" "$REFL_LOG" 2>/dev/null || true)

                if [[ $exit_code -ne 0 ]] && (( err_count >= 15 )); then
                    echo -e "\n${yellow}Reflector has encountered problems: $err_count mirrors are unavailable or have timed out.${reset}"
                    echo -e "${yellow}The connection might be unstable, or the mirrors are currently down.${reset}"

                    local force_cont
                    echo -ne "  ${white}Continue with the old mirrorlist anyway? [y/N]: ${reset}"
                    read -r force_cont

                    if [[ ! "$force_cont" =~ ^[Yy]$ ]]; then
                        echo -e "${red}The update was interrupted by the user.${reset}"
                        exit 1
                    fi

                    return 255
                fi

                return $exit_code
            }

            if [[ -n "$CUSTOM_REFLECTOR" ]]; then
                echo -e "  ${dim}Executing custom reflector command...${reset}"
                run_refl_and_check "$CUSTOM_REFLECTOR"
                local refl_res=$?
                if [[ $refl_res -eq 0 ]]; then
                    local new_mirror=$(get_current_mirror)
                    echo -e "  ${green}Custom Arch mirrors updated successfully. New mirror: ${white}$new_mirror${reset}\n"
                    REFL_SUCCESS=true
                elif [[ $refl_res -eq 255 ]]; then
                    echo -e "  ${yellow}Proceeding with old mirrors...${reset}\n"
                    return 0
                else
                    echo -e "  ${yellow}Custom reflector command failed. Falling back to default...${reset}"
                fi
            fi

            if ! $REFL_SUCCESS; then
                echo -e "  ${dim}Ranking mirrors... WARNINGS ARE EXPECTED.${reset}"
                run_refl_and_check "$DEFAULT_REFLECTOR"
                local refl_res=$?
                if [[ $refl_res -eq 0 ]]; then
                    local new_mirror=$(get_current_mirror)
                    echo -e "  ${green}Arch mirrors updated successfully. New mirror: ${white}$new_mirror${reset}\n"
                    return 0
                elif [[ $refl_res -eq 255 ]]; then
                    echo -e "  ${yellow}Proceeding with old mirrors...${reset}\n"
                    return 0
                else
                    echo -e "  ${red}Reflector failed (Try changing the reflector.conf settings).${reset}\n"
                    return 1
                fi
            fi
            return 0
        else
            echo -e "  ${red}Error: 'reflector' is not installed.${reset}\n"
            return 1
        fi
    fi
    return 1
}

# --- 6. Main Logic ---
log_step "Requesting Sudo access..."
if ! $DAEMON_MODE; then
    if ! sudo -v; then
        echo -e "${red}Error: Sudo authentication failed.${reset}"
        exit 1
    fi

    (
        while kill -0 "$$" 2>/dev/null; do
            sudo -n true 2>/dev/null
            sleep 60
        done
    ) &
    SUDO_KEEP_ALIVE_PID=$!
fi

AUR_HELPER=""
if [[ -n "${AUR_HELPER_OVERRIDE:-}" ]]; then
    if command -v "$AUR_HELPER_OVERRIDE" &>/dev/null; then
        AUR_HELPER="$AUR_HELPER_OVERRIDE"
    else
        echo -e "${yellow}Warning: Override AUR helper '$AUR_HELPER_OVERRIDE' not found. Falling back to auto-detect.${reset}"
        if command -v paru &>/dev/null; then AUR_HELPER="paru"
        elif command -v yay &>/dev/null; then AUR_HELPER="yay"
        fi
    fi
elif command -v paru &>/dev/null; then AUR_HELPER="paru"
elif command -v yay &>/dev/null; then AUR_HELPER="yay"
fi

echo -e "\n${blue}${bold}Checking for updates...${reset}"

if [[ -f /var/lib/pacman/db.lck ]]; then
    if $DAEMON_MODE; then exit 0; fi
    if sudo fuser /var/lib/pacman/db.lck >/dev/null 2>&1; then
        echo -e "${red}Error: Pacman database is locked (/var/lib/pacman/db.lck).${reset}"
        echo -e "${yellow}Another package manager process is running.${reset}"
        exit 1
    else
        echo -e "${yellow}Stale lock file found (/var/lib/pacman/db.lck), but no active process detected.${reset}"
        echo -ne "  ${white}Remove the stale lock file and continue? [y/N]: ${reset}"
        read -r rm_lock
        if [[ "$rm_lock" =~ ^[Yy]$ ]]; then
            sudo rm /var/lib/pacman/db.lck
            echo -e "${green}Lock file removed. Proceeding...${reset}"
        else
            echo -e "${red}Update aborted by user (database locked).${reset}"
            exit 1
        fi
    fi
fi

check_arch_news

MIRROR_LIST="/etc/pacman.d/mirrorlist"
did_prompt_mirrors=false

if [[ -f "$MIRROR_LIST" ]]; then
    now_ts=$(date +%s)
    file_ts=$(stat -c %Y "$MIRROR_LIST" 2>/dev/null || echo "$now_ts")

    mirror_age_days=$(( (now_ts - file_ts) / 86400 ))

    if (( mirror_age_days >= 7 )); then
        refresh_mirrors "Mirrors are old (${mirror_age_days} days)."
        did_prompt_mirrors=true
    fi
fi

if $DAEMON_MODE; then
    did_prompt_mirrors=true
    PROMPT_MIRROR_REFRESH=false
fi

if [[ "$did_prompt_mirrors" == false ]] && [[ "${PROMPT_MIRROR_REFRESH,,}" == "true" ]]; then
    refresh_mirrors "Pre-update mirror refresh is enabled in settings.conf."
fi

log_step "Copying local DB..."
cp -a --no-preserve=ownership /var/lib/pacman/local "$CHECK_DB/" > /dev/null 2>&1

if ! $DAEMON_MODE; then
    sudo chown -R root:root "$CHECK_DB"
    sudo chmod 755 "$CHECK_DB"
fi

MAX_RETRIES=1
attempt=0

while (( attempt <= MAX_RETRIES )); do
    log_step "Syncing temporary database (pacman -Sy)..."

    set -o pipefail
    if $DAEMON_MODE; then
        PACMAN_OPTS=""
        if pacman --disable-sandbox --version >/dev/null 2>&1; then
            PACMAN_OPTS="--disable-sandbox"
        fi

        if fakeroot pacman $PACMAN_OPTS -Sy --dbpath "$CHECK_DB" --logfile /dev/null 2>&1 | tee "$SYNC_LOG"; then
            PACMAN_EXIT=0
        else
            PACMAN_EXIT=$?
        fi
    else
        if sudo pacman -Sy --dbpath "$CHECK_DB" --logfile /dev/null 2>&1 | tee "$SYNC_LOG"; then
            PACMAN_EXIT=0
        else
            PACMAN_EXIT=$?
        fi
    fi
    set +o pipefail

    if grep -iqE "error|failed|timed out|could not resolve" "$SYNC_LOG"; then
        IS_DIRTY=1
    else
        IS_DIRTY=0
    fi

    err_count=$(grep -cEi "error|failed|timed out|could not resolve" "$SYNC_LOG" 2>/dev/null || true)

    if [[ $PACMAN_EXIT -eq 0 && $IS_DIRTY -eq 0 ]]; then
        break
    else
        if (( attempt < MAX_RETRIES )); then
            if refresh_mirrors "Failed to sync cleanly. Updating mirrors..."; then
                ((attempt++))
                log_step "Retrying sync..."
                continue
            fi
        fi

        if (( err_count >= 15 )); then
            if $DAEMON_MODE; then exit 1; fi
            echo -e "\n${yellow}The selected mirror might not be optimal.${reset}"
            echo -ne "  ${white}Continue anyway? [y/N]: ${reset}"
            read -r force_cont
            if [[ ! "$force_cont" =~ ^[Yy]$ ]]; then
                echo -e "${red}Update aborted by user.${reset}"
                exit 1
            fi
            break
        fi

        if [[ $PACMAN_EXIT -ne 0 ]]; then
            echo -e "${red}Error: Could not sync databases.${reset}"
            exit 1
        else
            echo -e "${yellow}Proceeding despite mirror warnings...${reset}"
            break
        fi
    fi
done

log_step "Calculating update list (pacman -Qu)..."

if ! $DAEMON_MODE; then
    sudo chown -R $(id -un):$(id -gn) "$CHECK_DB"
fi

ignored_pkgs=$(pacman-conf IgnorePkg 2>/dev/null | tr ' ' '\n')
ignored_groups=$(pacman-conf IgnoreGroup 2>/dev/null | tr ' ' '\n')

if [[ -n "$ignored_groups" ]]; then
    group_pkgs=$(pacman -Sgq $ignored_groups 2>/dev/null)
    ignored_pkgs="$ignored_pkgs"$'\n'"$group_pkgs"
fi

ignored_pkgs=$(echo "$ignored_pkgs" | sed '/^$/d' | sort -u)

repo_updates=$(LC_ALL=C pacman -Qu --dbpath "$CHECK_DB" --color never)

aur_updates=""
if [[ -n "$AUR_HELPER" ]]; then
    if aur_raw=$($AUR_HELPER -Qua --dbpath "$CHECK_DB" --color never 2>/dev/null); then
        aur_updates="$aur_raw"
    fi
fi

ignored_updates=""
if [[ -n "$ignored_pkgs" ]]; then
    awk_base='BEGIN { split(ig, a, "\n"); for (i in a) if(a[i] != "") ign[a[i]]=1 }'

    all_raw_updates=$(printf "%s\n%s" "$repo_updates" "$aur_updates" | sed '/^$/d')
    ignored_updates=$(echo "$all_raw_updates" | awk -v ig="$ignored_pkgs" "$awk_base ign[\$1]")

    [[ -n "$repo_updates" ]] && repo_updates=$(echo "$repo_updates" | awk -v ig="$ignored_pkgs" "$awk_base !ign[\$1]")
    [[ -n "$aur_updates" ]]  && aur_updates=$(echo "$aur_updates" | awk -v ig="$ignored_pkgs" "$awk_base !ign[\$1]")
fi

repo_pkgs=""
aur_pkgs=""

[[ -n "$repo_updates" ]] && repo_pkgs=$(echo "$repo_updates" | awk '{print $1}')
[[ -n "$aur_updates" ]] && aur_pkgs=$(echo "$aur_updates" | awk '{print $1}')

updates="$repo_updates"
[[ -n "$aur_updates" ]] && updates="$updates"$'\n'"$aur_updates"
updates=$(printf "%s\n" "$updates" | sed '/^$/d')

if [[ -z "$updates" ]]; then
    echo -e "${green}System is fully up to date.${reset}\n"

    if [[ -n "$ignored_updates" ]]; then
        echo -e "  ${magenta}${bold}Skipped Packages (IgnorePkg / IgnoreGroup):${reset}"
        while read -r pkg old_ver _ new_ver rest; do
            echo -e "    ${dim}- ${pkg}: ${gray}${old_ver}${reset} ${blue}→${reset} ${white}${new_ver}${reset}"
        done <<< "$ignored_updates"
        echo ""
    fi

    if [[ "$DAEMON_MODE" == true ]]; then
        rm -f "${XDG_RUNTIME_DIR:-/tmp}/arch-smart-update-notify-cache-${USER:-$(id -un)}"
    fi

    exit 0
fi

dependency_warnings=""
sim_error_warning=""

if [[ -n "$ignored_updates" ]]; then
    log_step "Checking for dependency conflicts with ignored packages..."

    sim_out=$(LC_ALL=C pacman -Sup --dbpath "$CHECK_DB" --print-format "%n" --noconfirm 2>&1)
    sim_exit=$?

    if [[ $sim_exit -ne 0 ]]; then
        if echo "$sim_out" | grep -qE "could not satisfy dependencies|conflicting dependencies|unresolvable package conflicts"; then
            dependency_warnings=$(echo "$sim_out" | awk '/could not satisfy dependencies|conflicting dependencies|unresolvable package conflicts/{flag=1; next} flag {print "    " $0}')

            if [[ -z "$dependency_warnings" ]]; then
                dependency_warnings=$(echo "$sim_out" | awk '/error:/ {flag=1} flag {print "    " $0}')
                [[ -z "$dependency_warnings" ]] && dependency_warnings=$(echo "$sim_out" | sed 's/^/    /')
            fi
        else
            sim_error_warning="    ${yellow}The update simulation failed due to a transaction error.${reset}\n${dim}$(echo "$sim_out" | sed 's/^/      /')${reset}"
        fi
    fi
fi

pkg_count=$(grep -c . <<< "$updates")
if [[ -n "$aur_updates" ]]; then
    aur_count=$(grep -c . <<< "$aur_updates")
else
    aur_count=0
fi

log_step "Found $pkg_count updates ($aur_count from AUR). Starting detailed analysis..."
echo -e "${blue}${bold}Analyzing updates: ${white}$pkg_count packages${reset}"

all_pkgs=$(echo "$updates" | awk '{print $1}')

log_step "Fetching remote metadata (pacman -Si)..."
declare -A NEW_DATA

parse_metadata() {
    local default_repo="$1"
    awk -v def_repo="$default_repo" '
        /^Name[ \t]*:/ {n=$0; sub(/^[^:]*:[ \t]*/, "", n)}
        /^Repository[ \t]*:/ {r=$0; sub(/^[^:]*:[ \t]*/, "", r)}
        /^(Build Date|Last Modified)[ \t]*:/ {b=$0; sub(/^[^:]*:[ \t]*/, "", b)}
        /^Download Size[ \t]*:/ {s=$0; sub(/^[^:]*:[ \t]*/, "", s)}
        /^Description[ \t]*:/ {d=$0; sub(/^[^:]*:[ \t]*/, "", d); gsub(/[|\t~]/, " ", d)}
        /^$/ {
            if (n) {
                print n "~|~" (r ? r : def_repo) "|" b "|" (s ? s : "N/A") "|" d
                n=""; r=""; b=""; s=""; d=""
            }
        }
        END {if (n) print n "~|~" (r ? r : def_repo) "|" b "|" (s ? s : "N/A") "|" d}
    '
}

if [[ -n "$repo_pkgs" ]]; then
    while IFS='' read -r line; do
        NEW_DATA["${line%%~|~*}"]="${line#*~|~}"
    done < <(echo "$repo_pkgs" | xargs env LC_ALL=C pacman -Si --dbpath "$CHECK_DB" --color never 2>/dev/null | parse_metadata "")
fi

if [[ -n "$aur_pkgs" && -n "$AUR_HELPER" ]]; then
    log_step "Fetching AUR metadata..."
    while IFS='' read -r line; do
        NEW_DATA["${line%%~|~*}"]="${line#*~|~}"
    done < <(echo "$aur_pkgs" | xargs env LC_ALL=C $AUR_HELPER -Si 2>/dev/null | parse_metadata "AUR")
fi

log_step "Fetching local metadata (pacman -Qi)..."
declare -A OLD_DATA
while IFS='|' read -r name bdate reason; do
    [[ -z "${OLD_DATA[$name]}" ]] && OLD_DATA["$name"]="$bdate|$reason"
done < <(echo "$all_pkgs" | xargs env LC_ALL=C pacman -Qi 2>/dev/null | awk '
    /^Name[ \t]*:/ {n=$0; sub(/^[^:]*:[ \t]*/, "", n)}
    /^Build Date[ \t]*:/ {b=$0; sub(/^[^:]*:[ \t]*/, "", b)}
    /^Install Reason[ \t]*:/ {r=$0; sub(/^[^:]*:[ \t]*/, "", r)}
    /^$/ {
        if (n) {
            print n "|" b "|" r
            n=""; b=""; r=""
        }
    }
    END {if (n) print n "|" b "|" r}
')

total_download_size="0.00 MiB"
if [[ -n "$repo_pkgs" ]]; then
    total_download_size=$(echo "$repo_pkgs" | xargs env LC_ALL=C pacman -Si --dbpath "$CHECK_DB" 2>/dev/null | awk '
        /^Download Size[ \t]*:/ {
            sub(/^[^:]*:[ \t]*/, "")

            val = $1
            unit = $2

            if (unit == "KiB") val /= 1024
            else if (unit == "GiB") val *= 1024
            else if (unit == "B") val /= (1024 * 1024)

            sum += val
        }
        END {
            if (sum >= 1024) {
                printf "%.2f GiB", sum / 1024
            } else {
                printf "%.2f MiB", sum + 0
            }
        }
    ')
fi

log_step "Processing data and calculating diffs..."

now=$(date +%s)
current_idx=0

max_name=7
max_old=3
max_new=3
max_repo=4
max_size=4

declare -A DATE_CACHE

while read -r pkgname old_ver _ new_ver _rest; do
    ((current_idx++))
    percent=$(( current_idx * 100 / pkg_count ))

    if ! $DAEMON_MODE; then
        if (( percent % 5 == 0 || current_idx == pkg_count )); then
            filled=$(( percent / 5 ))
            empty=$(( 20 - filled ))
            printf "\r\033[2K  ${gray}Analysis: ${blue}["
            printf "%${filled}s" | tr ' ' '='
            printf ">"
            printf "%${empty}s" | tr ' ' '-'
            printf "] ${percent}%%${reset}"
        fi
    fi

    IFS='|' read -r repo date_new size desc <<< "${NEW_DATA[$pkgname]}"
    IFS='|' read -r date_old reason <<< "${OLD_DATA[$pkgname]}"

    is_explicit=0
    [[ "$reason" == *"Explicitly"* ]] && is_explicit=1

    (( ${#pkgname} > max_name )) && max_name=${#pkgname}
    (( ${#old_ver} > max_old )) && max_old=${#old_ver}
    (( ${#new_ver} > max_new )) && max_new=${#new_ver}
    (( ${#repo} > max_repo )) && max_repo=${#repo}
    (( ${#size} > max_size )) && max_size=${#size}

    epoch_new=0
    fmt_date_new=""
    diff_hours=9999

    if [[ -n "$date_new" && "$date_new" != "N/A" ]]; then
        if [[ -z "${DATE_CACHE["$date_new"]}" ]]; then
            DATE_CACHE["$date_new"]=$(LC_TIME=C date -d "$date_new" +'%s|%d %b %H:%M' 2>/dev/null || echo "0|")
        fi

        IFS='|' read -r epoch_new fmt_date_new <<< "${DATE_CACHE["$date_new"]}"

        if [[ -n "$epoch_new" ]] && (( epoch_new > 0 )); then
            diff_hours=$(( (now - epoch_new) / 3600 ))
        fi
    fi

    is_nuke=0
    is_crit=0
    is_feat=0

    [[ ${NUKE_MAP["$pkgname"]} ]] && is_nuke=1
    [[ ${CRIT_MAP["$pkgname"]} ]] && is_crit=1
    [[ ${FEAT_MAP["$pkgname"]} ]] && is_feat=1

    if (( is_nuke )); then
        pkg_level=0
    elif (( is_crit )); then
        pkg_level=1
    elif (( is_feat )); then
        pkg_level=2
    else
        pkg_level=3
    fi

    upd_type=$(get_update_type "$old_ver" "$new_ver" "$pkg_level")

    sort_key=$(printf "%d.%05d" "$pkg_level" "$diff_hours")

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$sort_key" "$diff_hours" "$pkg_level" "$upd_type" "$pkgname" "$old_ver" "$new_ver" \
        "$repo" "$size" "$is_explicit" "$epoch_new" "$fmt_date_new" "$desc" >> "$OUTPUT_FILE"

done <<< "$updates"

echo -e "\n"

# --- 7. Table Output ---
w_age=8
w_stat=8
w_repo=$(( max_repo ))
w_type=6
w_name=$(( max_name ))
w_old=$(( max_old ))
w_new=$(( max_new ))
w_size=$(( max_size ))
w_date=12

term_cols=$(tput cols 2>/dev/null || echo 120)
used_width=$(( w_age + 1 + w_stat + 1 + w_repo + 1 + w_type + 1 + w_name + 1 + w_old + 3 + w_new + 1 + w_size + 1 + w_date + 1 ))
w_desc=$(( term_cols - used_width - 1 ))

if (( w_desc < 5 )); then
    w_desc=0
fi

sep_line=$(printf "%${term_cols}s" | tr ' ' '-')

printf "${dim}%s${reset}\n" "$sep_line"

fmt_center() {
    local str="$1"
    local width="$2"
    local len=${#str}
    if (( len >= width )); then
        printf "%s" "$str"
    else
        local l_pad=$(( (width - len) / 2 ))
        local r_pad=$(( width - len - l_pad ))
        printf "%*s%s%*s" $l_pad "" "$str" $r_pad ""
    fi
}

h_age=$(fmt_center "AGE" "$w_age")
h_stat=$(fmt_center "STATUS" "$w_stat")
h_repo=$(fmt_center "REPO" "$w_repo")
h_type=$(fmt_center "TYPE" "$w_type")
h_size=$(fmt_center "SIZE" "$w_size")
h_date=$(fmt_center "NEW DATE" "$w_date")

printf -v h_name "%-${w_name}s" "PACKAGE"
printf -v h_old "%${w_old}s" "OLD"
printf -v h_new "%-${w_new}s" "NEW"

h_desc="DESCRIPTION"
(( w_desc == 0 )) && h_desc=""

printf "${bold}${gray}%s %s %s %s %s %s   %s %s %s %s${reset}\n" \
    "$h_age" "$h_stat" "$h_repo" "$h_type" "$h_name" "$h_old" "$h_new" "$h_size" "$h_date" "$h_desc"

printf "${dim}%s${reset}\n" "$sep_line"

sort -n "$OUTPUT_FILE" | while IFS=$'\t' read -r key diff_hours pkg_level upd_type pkgname old_ver new_ver repo size is_explicit epoch_new fmt_date_new desc; do

    if (( diff_hours == 9999 )); then age_disp="[?]"; age_col=$dim
    else
        age_disp="[${diff_hours}h]"
        if (( diff_hours < 12 )); then age_col="${red}${bold}"
        elif (( diff_hours < 48 )); then age_col="${yellow}"
        else age_col="${green}"; fi
    fi
    printf -v f_age "%-${w_age}s" "$age_disp"
    out_age="${age_col}${f_age}${reset}"

    if (( pkg_level == 0 )); then
        out_stat="${bg_nuke} ☢ NUKE ${reset}"
    elif (( pkg_level == 1 )); then
        out_stat="${bg_crit} ! CRIT ${reset}"
    elif (( pkg_level == 2 )); then
        out_stat="${bg_feat} * FEAT ${reset}"
    else
        out_stat="$(printf "%-${w_stat}s" " ")"
    fi

    printf -v f_repo "%-${w_repo}s" "$repo"
    if [[ "$repo" == "AUR" ]]; then
        out_repo="${magenta}${f_repo}${reset}"
    else
        out_repo="${dim}${f_repo}${reset}"
    fi

    type_col=$(get_type_color "$upd_type")
    printf -v f_type "%-${w_type}s" "$upd_type"
    out_type="${type_col}${f_type}${reset}"

    if (( is_explicit == 1 )); then
        name_col="${white}${bold}"
    else
        name_col="${gray}"
    fi
    printf -v f_name "%-${w_name}s" "$pkgname"
    out_name="${name_col}${f_name}${reset}"

    printf -v f_date_padded "%-${w_date}s" "$fmt_date_new"
    out_date_new="${dim}${f_date_padded}${reset}"

    printf -v f_size "%${w_size}s" "$size"
    out_size="${white}${f_size}${reset}"

    if (( w_desc > 0 )); then
        if (( ${#desc} > w_desc )); then
            out_desc="${dim}${desc:0:$((w_desc-1))}…${reset}"
        else
            out_desc="${dim}${desc}${reset}"
        fi
    else
        out_desc=""
    fi

    printf "%b %b %b %b %b ${gray}%${w_old}s${reset} ${blue}→${reset} ${white}%-${w_new}s${reset} %b %b %b\n" \
        "$out_age" "$out_stat" "$out_repo" "$out_type" "$out_name" \
        "$old_ver" "$new_ver" "$out_size" "$out_date_new" "$out_desc"

done

printf "${dim}%s${reset}\n" "$sep_line"
echo -e "  ${gray}Total Download Size: ${white}${bold}${total_download_size}${reset}"

give_advice() {
    local now=$(date +%s)

    local T_MIRROR_SEC=$(( T_MIRROR_H * 3600 ))
    local T_FEAT_SEC=$(( T_FEAT_H * 3600 ))
    local T_CRIT_SEC=$(( T_CRIT_H * 3600 ))
    local T_DE_SEC=$(( T_DE_H * 3600 ))
    local T_NUKE_SEC=$(( T_NUKE_H * 3600 ))

    local fresh_pkg_count=0
    local fresh_feat_count=0
    local fresh_de_count=0
    local fresh_crit_count=0
    local fresh_nuke_count=0

    local min_age_norm_sec=999999999
    local min_age_feat_sec=999999999
    local min_age_de_sec=999999999
    local min_age_crit_sec=999999999
    local min_age_nuke_sec=999999999

    local risky_norm_pkg=""
    local risky_feat_pkg=""
    local risky_de_pkg=""
    local risky_crit_pkg=""
    local risky_nuke_pkg=""

    local DE_PATTERN="^(plasma-|gnome-|hyprland|kwin|mutter|cinnamon|xfce4|qt[56]-|gtk[34]|kf[56]-|frameworkintegration)"

    while IFS=$'\t' read -r _ _ pkg_level upd_type pkgname _ _ repo _ _ epoch_new _ _; do
        [[ "$repo" == "AUR" ]] && continue

        local pkg_ts=${epoch_new:-0}
        (( pkg_ts == 0 )) && continue

        local age_sec=$(( now - pkg_ts ))
        (( age_sec < 0 )) && age_sec=0

        local is_patch_override=0
        if [[ "${IGNORE_PATCH_TIMERS,,}" == "true" && "$upd_type" == "Patch" ]]; then
            is_patch_override=1
        fi

        if (( is_patch_override == 0 )); then
            if (( pkg_level == 0 )); then
                if (( age_sec < T_NUKE_SEC )); then
                    ((fresh_nuke_count++))
                    if (( age_sec < min_age_nuke_sec )); then
                        min_age_nuke_sec=$age_sec
                        risky_nuke_pkg=$pkgname
                    fi
                fi
            fi

            if (( pkg_level == 1 )); then
                if (( age_sec < T_CRIT_SEC )); then
                    ((fresh_crit_count++))
                    if (( age_sec < min_age_crit_sec )); then
                        min_age_crit_sec=$age_sec
                        risky_crit_pkg=$pkgname
                    fi
                fi
            fi

            if [[ "$pkgname" =~ $DE_PATTERN ]]; then
                if (( age_sec < T_DE_SEC )); then
                    ((fresh_de_count++))
                    if (( age_sec < min_age_de_sec )); then
                        min_age_de_sec=$age_sec
                        risky_de_pkg=$pkgname
                    fi
                fi
            fi

            if (( pkg_level == 2 )); then
                if (( age_sec < T_FEAT_SEC )); then
                    ((fresh_feat_count++))
                    if (( age_sec < min_age_feat_sec )); then
                        min_age_feat_sec=$age_sec
                        risky_feat_pkg=$pkgname
                    fi
                fi
            fi
        fi

        if (( age_sec < T_MIRROR_SEC )); then
            ((fresh_pkg_count++))
            if (( age_sec < min_age_norm_sec )); then
                min_age_norm_sec=$age_sec
                risky_norm_pkg=$pkgname
            fi
        fi

    done < "$OUTPUT_FILE"

    echo -e "${dim}---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------${reset}"

    local max_wait_sec=0
    local verdict_level=0 # 0=Safe, 1=Yellow, 2=Red, 3=NUCLEAR
    local reasons=()

    if (( fresh_nuke_count > 0 )); then
        local wait=$(( T_NUKE_SEC - min_age_nuke_sec ))
        (( wait > max_wait_sec )) && max_wait_sec=$wait
        verdict_level=3
        reasons+=("${red}${bold}HIGH RISK${dim} System Core updates (< ${T_NUKE_H}h). Wait for stability! (e.g., $risky_nuke_pkg)")
    fi

    if (( fresh_crit_count > 0 )); then
        local wait=$(( T_CRIT_SEC - min_age_crit_sec ))
        (( wait > max_wait_sec )) && max_wait_sec=$wait
        (( verdict_level < 2 )) && verdict_level=2
        reasons+=("Critical updates (< ${T_CRIT_H}h). (e.g., $risky_crit_pkg)")
    fi

    if (( fresh_de_count > 0 )); then
        local wait=$(( T_DE_SEC - min_age_de_sec ))
        (( wait > max_wait_sec )) && max_wait_sec=$wait
        (( verdict_level < 2 )) && verdict_level=2
        reasons+=("Major DE update detected (< ${T_DE_H}h). (e.g., $risky_de_pkg)")
    fi

    if (( fresh_feat_count > 0 )); then
        local wait=$(( T_FEAT_SEC - min_age_feat_sec ))
        (( wait > max_wait_sec )) && max_wait_sec=$wait
        (( verdict_level < 1 )) && verdict_level=1
        reasons+=("Fresh Feature updates (< ${T_FEAT_H}h). (e.g., $risky_feat_pkg)")
    fi

    if (( fresh_pkg_count > 0 )); then
        local wait=$(( T_MIRROR_SEC - min_age_norm_sec ))
        (( wait > max_wait_sec )) && max_wait_sec=$wait
        (( verdict_level < 1 )) && verdict_level=1
        reasons+=("Mirrors might not be fully synced (< ${T_MIRROR_H}h). (e.g., $risky_norm_pkg)")
    fi

    local color=$green
    local verdict="SAFE"

    case $verdict_level in
        1) color=$yellow; verdict="REVIEW" ;;
        2) color=$red; verdict="HOLD" ;;
        3) color="${red}${bold}"; verdict="DANGER" ;;
    esac

    printf "  ${bold}ADVISOR:${reset} "

    if (( max_wait_sec == 0 )); then
        echo -e "${green}${bold}GO FOR IT!${reset} ${dim}(Packages have stabilized. Mirrors synced.)${reset}"
        GLOBAL_ADVISOR_SAFE=true
    else
        local target_time=$(date -d "@$(( now + max_wait_sec ))" +%H:%M)

        local wait_h=$(( max_wait_sec / 3600 ))
        local wait_m=$(( (max_wait_sec % 3600) / 60 ))

        local dur_str="+"
        (( wait_h > 0 )) && dur_str+="${wait_h}h "
        dur_str+="${wait_m}m"

        echo -e "${color}${bold}$verdict${reset} ${white}Recommend waiting until ${bold}$target_time${reset} ($dur_str)"

        if (( ${#reasons[@]} > 0 )); then
             echo -ne "           ${dim}Reason: ${reasons[0]}${reset}"
             for (( i=1; i<${#reasons[@]}; i++ )); do
                 echo -ne "\n                   ${dim}+ ${reasons[$i]}${reset}"
             done
             echo ""
        fi
        GLOBAL_ADVISOR_SAFE=false
    fi
    echo -e "${dim}---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------${reset}"
}

give_advice

if [[ -n "$ignored_updates" ]]; then
    echo -e "\n  ${magenta}${bold}Skipped Packages (IgnorePkg / IgnoreGroup):${reset}"
    while read -r pkg old_ver _ new_ver rest; do
        echo -e "    ${dim}- ${pkg}: ${gray}${old_ver}${reset} ${blue}→${reset} ${white}${new_ver}${reset}"
    done <<< "$ignored_updates"

    if [[ -n "$dependency_warnings" ]]; then
        echo -e "\n  ${bg_nuke}${white}${bold}DEPENDENCY BREAKAGE DETECTED ⚠ ${reset}"
        echo -e "  ${red}Updating now will likely abort because of unresolved dependencies!${reset}"
        echo -e "  ${gray}Pacman reports the following conflicts:${reset}"
        echo -e "${red}${dependency_warnings}${reset}\n"
    elif [[ -n "$sim_error_warning" ]]; then
        echo -e "\n${sim_error_warning}\n"
    else
        echo -e "\n    ${green}No dependency conflicts detected from skipped packages ${dim}(Official repos only)${green}.${reset}"
    fi
fi

if [[ "$DAEMON_MODE" == true ]]; then
    CACHE_FILE="${XDG_RUNTIME_DIR:-/tmp}/arch-smart-update-notify-cache-${USER:-$(id -un)}"

    if [[ "$GLOBAL_ADVISOR_SAFE" == true ]] && (( pkg_count > 0 )) && command -v notify-send >/dev/null 2>&1; then
        OLD_COUNT=0
        [[ -f "$CACHE_FILE" ]] && OLD_COUNT=$(cat "$CACHE_FILE" 2>/dev/null)

        if (( pkg_count != OLD_COUNT )); then
            notify-send -a "Arch Smart Update" -u normal -i software-update-available \
                "Safe Updates Available\nFound $pkg_count updates ($aur_count AUR).\nReady to install."
            echo "$pkg_count" > "$CACHE_FILE"
        fi
    fi
    exit 0
fi

# --- 8. Update Request ---
check_pending_updates() {
    local pending
    pending=$(LC_ALL=C pacman -Qu 2>/dev/null)
    if [[ -n "$ignored_pkgs" && -n "$pending" ]]; then
        pending=$(echo "$pending" | awk -v ig="$ignored_pkgs" '
            BEGIN { split(ig, a, "\n"); for (i in a) if(a[i] != "") ign[a[i]]=1 }
            { if (!ign[$1]) print $0 }
        ')
    fi
    echo "$pending"
}

HAS_EOS=false
HAS_TOPGRADE=false

command -v eos-update &> /dev/null && HAS_EOS=true
command -v topgrade &> /dev/null && HAS_TOPGRADE=true

if [[ ${#CUSTOM_CMDS[@]} -gt 0 ]]; then
    if [[ ${#CUSTOM_CMDS[@]} -eq 1 ]]; then
        PROMPT_CMD="${CUSTOM_CMDS[0]}"
    else
        PROMPT_CMD="Custom config (${#CUSTOM_CMDS[@]} commands)"
    fi
elif $HAS_EOS && $HAS_TOPGRADE; then
    PROMPT_CMD="eos-update && topgrade"
elif $HAS_EOS; then
    PROMPT_CMD="eos-update"
elif $HAS_TOPGRADE; then
    PROMPT_CMD="topgrade"
else
    if [[ -n "$AUR_HELPER" ]]; then
        PROMPT_CMD="$AUR_HELPER -Syu"
    else
        PROMPT_CMD="sudo pacman -Syu"
    fi
fi

sudo -v

echo -ne "\n  ${bold}${white}Apply updates?${reset} ${dim}(${PROMPT_CMD})${reset} [Y/n]: "
read -r answer

if [[ "$answer" =~ ^[Yy]$ || -z "$answer" ]]; then
    sudo -v
    echo -e "\n"
    backup_pacman_db
    UPDATE_SUCCESS=false

    if [[ ${#CUSTOM_CMDS[@]} -gt 0 ]]; then
        echo -e "${blue}${bold}Running custom update commands...${reset}\n"
        UPDATE_SUCCESS=true

        for cmd in "${CUSTOM_CMDS[@]}"; do
            echo -e "  ${dim}Executing: ${white}$cmd${reset}"
            bash -c "$cmd"
            core_exit=$?

            if [[ $core_exit -ne 0 ]]; then
                UPDATE_SUCCESS=false
                echo -e "\n${red}Command failed with exit code $core_exit: $cmd${reset}"
                break
            fi
        done

        if $UPDATE_SUCCESS; then
            if [[ -n "$(check_pending_updates)" ]]; then
                echo -e "\n${yellow}Custom commands finished successfully, but standard pacman updates were skipped.${reset}"
                echo -e "  ${dim}Make sure your custom commands include a package manager update (e.g., 'paru -Syu').${reset}"
            fi
        fi

    elif $HAS_EOS && $HAS_TOPGRADE; then
        echo -e "${blue}${bold}Running eos-update (Keyrings & Packages)...${reset}\n"
        eos-update
        core_exit=$?

        pending_updates=$(check_pending_updates)

        if [[ -z "$pending_updates" && $core_exit -eq 0 ]]; then
            echo -e "\n${green}Core updates applied successfully.${reset}"
            echo -e "\n${blue}${bold}Running Topgrade (Firmware, Flatpaks, Dotfiles)...${reset}\n"
            topgrade && UPDATE_SUCCESS=true
        else
            echo -e "\n${yellow}eos-update was cancelled or did not fully apply updates.${reset}"
            echo -ne "  ${white}Run topgrade anyway? (Flatpaks/AUR etc) [y/N]: ${reset}"
            read -r force_extra
            if [[ "$force_extra" =~ ^[Yy]$ ]]; then
                topgrade && UPDATE_SUCCESS=true
            else
                echo -e "  ${dim}Skipping extra updates.${reset}\n"
            fi
        fi

    elif $HAS_EOS; then
        eos-update
        core_exit=$?
        if [[ $core_exit -eq 0 && -z "$(check_pending_updates)" ]]; then
            UPDATE_SUCCESS=true
        fi

    elif $HAS_TOPGRADE; then
        echo -e "${blue}${bold}Running Topgrade (System, AUR, Firmware, etc.)...${reset}\n"
        topgrade && UPDATE_SUCCESS=true

    else
        echo -e "${blue}${bold}Running standard system update...${reset}\n"
        if [[ -n "$AUR_HELPER" ]]; then
            $AUR_HELPER -Syu
            core_exit=$?
        else
            sudo pacman -Syu
            core_exit=$?
        fi

        if [[ $core_exit -eq 0 && -z "$(check_pending_updates)" ]]; then
            UPDATE_SUCCESS=true
        fi
    fi

    if $UPDATE_SUCCESS; then
        rm -f "${XDG_RUNTIME_DIR:-/tmp}/arch-smart-update-notify-cache-${USER:-$(id -un)}"

        if [[ "${ENABLE_BACKGROUND_CHECK,,}" == "true" ]]; then
            systemctl --user restart arch-smart-update.timer >/dev/null 2>&1
        fi

        echo -e "\n${green}Update process finished successfully.${reset}\n"
    else
        echo -e "\n${red}Update process completed with errors, partial updates, or was cancelled.${reset}\n"
    fi

else
    echo -e "  ${yellow}Operation cancelled.${reset}\n"
fi

sleep 0.1
exit 0
