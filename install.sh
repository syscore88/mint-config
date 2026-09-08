#!/bin/bash
# ==========================================================
# KOMPLEKSOWY SKRYPT KONFIGURACYJNY SYSTEMU (LINUX MINT)
# ==========================================================

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/sbin:/sbin:$PATH"

detect_system_lang() { 
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl_PL* || "$sys_lang" == pl* ]]; then
        echo "pl"
    else
        echo "en"
    fi
}
SCRIPT_LANG="$(detect_system_lang)"

detect_system_locale() {
    local sys_locale="${LANG:-}"
    [[ -z "$sys_locale" ]] && sys_locale="${LC_ALL:-${LC_MESSAGES:-}}"
    [[ -z "$sys_locale" ]] && sys_locale="en_US.UTF-8"

    if command -v locale &>/dev/null; then
        local available
        available="$(locale -a 2>/dev/null)"
        if echo "$available" | grep -qiF "$sys_locale" || \
           echo "$available" | grep -qiF "$(echo "$sys_locale" | sed 's/UTF-8/utf8/')"; then
            echo "$sys_locale"
            return
        fi
    fi
    echo "en_US.UTF-8"
}
SYSTEM_LOCALE="$(detect_system_locale)"

INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERR='\033[0;31m'
NC='\033[0m'

TMP_LOG="$(mktemp /tmp/mint-install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

cleanup_on_exit() {
    local exit_code=$?
    printf '\033[?7h' >&3
    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✖ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
        else
            echo -e "${ERR}✖ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
        fi
    fi
    rm -f "$TMP_LOG"
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

show_progress() {
    local step=$1
    local total=$2
    local msg=$3
    local percent=$(( step * 100 / total ))

    local cols
    cols=$(tput cols 2>/dev/null)
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    local bar_width=50
    local reserved=12
    if (( cols - reserved < bar_width )); then
        bar_width=$(( cols - reserved ))
        (( bar_width < 10 )) && bar_width=10
    fi

    local overhead=$(( bar_width + reserved ))
    local avail=$(( cols - overhead ))
    if (( avail < 5 )); then avail=5; fi
    if (( ${#msg} > avail )); then
        msg="${msg:0:$((avail - 1))}…"
    fi

    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    local bar_filled=""
    local bar_empty=""
    if [ $filled -gt 0 ]; then printf -v bar_filled '%*s' "$filled" ''; bar_filled="${bar_filled// /#}"; fi
    if [ $empty -gt 0 ]; then printf -v bar_empty '%*s' "$empty" ''; bar_empty="${bar_empty// /-}"; fi

    printf "\r\033[K[\033[1;32m%s\033[0;90m%s\033[0m] %3d%% | \033[1;36m%s\033[0m" "$bar_filled" "$bar_empty" "$percent" "$msg" >&3
}

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    MSG_PHASE_1="[1/4] Konfiguracja repozytoriów i optymalizacja systemu..."
    MSG_PHASE_2="[2/4] Instalacja pakietów systemowych, Flatpak i .deb..."
    MSG_PHASE_3="[3/4] Konfiguracja usług i środowiska ZSH..."
    MSG_PHASE_4="[4/4] Zakończenie i sprzątanie..."
else
    MSG_PHASE_1="[1/4] Repository configuration and system optimization..."
    MSG_PHASE_2="[2/4] Installing system packages, Flatpak, and .deb..."
    MSG_PHASE_3="[3/4] Configuring services and ZSH environment..."
    MSG_PHASE_4="[4/4] Finishing up and cleaning..."
fi

TOTAL_STEPS=12

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CURRENT_USER=$(whoami)
DEB_DIR="/tmp/debs_$$"

source /etc/os-release
OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
echo "Wykryty system: ${PRETTY_NAME:-nieznany}, codename: ${OS_CODENAME:-nieznany}"
if [[ "$EUID" -eq 0 ]]; then
    if [[ "$SCRIPT_LANG" == "pl" ]]; then
        echo -e "${ERR}✖ Nie uruchamiaj skryptu jako root. Użyj zwykłego użytkownika z sudo.${NC}" >&3
    else
        echo -e "${ERR}✖ Do not run as root. Use a regular user with sudo privileges.${NC}" >&3
    fi
    exit 1
fi

printf '\033[?7h\n' >&3

RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
USE_RUN0=0
if ! command -v visudo >/dev/null 2>&1 || sudo --version 2>/dev/null | grep -qi "run0"; then
    USE_RUN0=1
fi

sudo -v

if [[ "$USE_RUN0" -eq 1 ]]; then
    printf 'polkit._run0_nopasswd.push("%s");\n' "$CURRENT_USER" | sudo tee "$RUN0_NOPASSWD_FILE" > /dev/null
    sudo systemctl try-restart polkit 2>/dev/null || true
else
    SUDOERS_TMP="$(mktemp)"
    echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"
    if sudo visudo -cf "$SUDOERS_TMP" &>/dev/null; then
        sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/99-temp-installer
    else
        rm -f "$SUDOERS_TMP"
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✖ Nieprawidłowa składnia reguły sudoers - przerywam.${NC}" >&3
        else
            echo -e "${ERR}✖ Invalid sudoers rule syntax - aborting.${NC}" >&3
        fi
        exit 1
    fi
    rm -f "$SUDOERS_TMP"
fi

printf '\033[?7l' >&3

safe_apt_update() {
    local out rc
    set +e
    out=$(sudo apt-get update -yq 2>&1)
    rc=$?
    set -e
    echo "$out"
    [[ $rc -eq 0 ]] && return 0

    local broken_urls
    broken_urls=$(echo "$out" | grep -oP '(?:Błąd|Err|Fehler|Erreur|Errore|Erro):[0-9]+ \Khttps?://\S+')
    broken_urls+=$'\n'"$(echo "$out" | grep -oP '^\S+:[0-9]+ \Khttps?://\S+(?= )')"
    broken_urls=$(echo "$broken_urls" | sort -u | grep -v '^$' || true)
    local removed=0
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        local host_path="${url#http://}"
        host_path="${host_path#https://}"
        for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
            [[ -f "$f" ]] || continue
            if grep -qF "$host_path" "$f" 2>/dev/null; then
                sudo rm -f "$f"
                removed=1
            fi
        done
    done <<< "$broken_urls"

    if [[ $removed -eq 1 ]]; then
        wait_for_apt
        sudo apt-get update -yq || true
        return 0
    else
        return 0
    fi
}

wait_for_apt() {
    sudo systemctl stop packagekit 2>/dev/null || true
    while sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo killall -0 apt apt-get dpkg 2>/dev/null; do
        sleep 3
    done
}

add_ppa_and_install() {
    local ppa="$1"; shift
    local packages=("$@")

    if ! command -v add-apt-repository &>/dev/null; then return 1; fi
    if ! sudo add-apt-repository -y "ppa:$ppa" 2>/dev/null; then return 1; fi

    wait_for_apt
    if sudo apt-get update -yq && sudo apt-get install -yq "${packages[@]}"; then
        return 0
    fi

    sudo add-apt-repository --remove -y "ppa:$ppa" 2>/dev/null || true
    wait_for_apt
    sudo apt-get update -yq || true
    return 1
}

# ==========================================================
# 1. PRZYGOTOWANIE I REPOZYTORIA
# ==========================================================
show_progress 0 $TOTAL_STEPS "$MSG_PHASE_1"

if [[ -f "$SCRIPT_DIR/.update.sh" ]]; then
    cp -af "$SCRIPT_DIR/.update.sh" ~/.update.sh
    chmod +x ~/.update.sh
fi

if [[ -d "$SCRIPT_DIR/.local" ]]; then
    mkdir -p ~/.local
    cp -afT "$SCRIPT_DIR/.local" ~/.local
fi

if [[ -d "$SCRIPT_DIR/.config" ]]; then
    mkdir -p ~/.config
    cp -afT "$SCRIPT_DIR/.config" ~/.config
fi

wait_for_apt
sudo sed -i '/cdrom/s/^/#/' /etc/apt/sources.list 2>/dev/null || true
sudo dpkg --add-architecture i386 || true

if command -v add-apt-repository &>/dev/null; then
    sudo add-apt-repository -y universe  2>/dev/null || true
    sudo add-apt-repository -y multiverse 2>/dev/null || true
fi

show_progress 1 $TOTAL_STEPS "$MSG_PHASE_1"

wait_for_apt
safe_apt_update
for pkg in curl wget gnupg pciutils dconf-cli; do
    sudo apt-get install -yq "$pkg" || true
done
sudo mkdir -p /etc/apt/keyrings
sudo chmod 755 /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/google-chrome.gpg ]; then
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor --yes -o /etc/apt/keyrings/google-chrome.gpg
    sudo chmod 644 /etc/apt/keyrings/google-chrome.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
fi

show_progress 2 $TOTAL_STEPS "$MSG_PHASE_1"

sudo mkdir -p /usr/share/keyrings
sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
BRAVE_KEY_ID="0686B78420038257"
BRAVE_GNUPGHOME="$(mktemp -d)"
BRAVE_KEY_OK=0
if gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keyserver.ubuntu.com --recv-keys "$BRAVE_KEY_ID" \
    || gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keys.openpgp.org --recv-keys "$BRAVE_KEY_ID"; then
    if gpg --homedir "$BRAVE_GNUPGHOME" --export "$BRAVE_KEY_ID" | sudo tee /usr/share/keyrings/brave-browser-archive-keyring.gpg > /dev/null \
        && [[ -s /usr/share/keyrings/brave-browser-archive-keyring.gpg ]]; then
        BRAVE_KEY_OK=1
    fi
fi
rm -rf "$BRAVE_GNUPGHOME"

if [[ "$BRAVE_KEY_OK" -eq 1 ]]; then
    sudo chmod 644 /usr/share/keyrings/brave-browser-archive-keyring.gpg
    sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources https://brave-browser-apt-release.s3.brave.com/brave-browser.sources || true
else
    sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
fi

wait_for_apt
safe_apt_update
sudo apt-get upgrade -yq || true

show_progress 3 $TOTAL_STEPS "$MSG_PHASE_1"

wait_for_apt
sudo apt-get install -yq linux-firmware || true

PACKAGES_REMOVE=()
if [[ ${#PACKAGES_REMOVE[@]} -gt 0 ]]; then
    for pkg in "${PACKAGES_REMOVE[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            sudo apt-get purge -yq "$pkg" || true
        fi
    done
fi
sudo apt-get autoremove -yq || true

# ==========================================================
# 2. INSTALACJA PAKIETÓW I FLATPAK
# ==========================================================
show_progress 4 $TOTAL_STEPS "$MSG_PHASE_2"

wait_for_apt
PACKAGES_INSTALL=(
    google-chrome-stable brave-origin gmic mixxx kdenlive gimp soundconverter
    vim dconf-editor hunspell-pl bleachbit profile-sync-daemon git build-essential
    unrar-free mc btrfs-progs exfatprogs ntfs-3g os-prober
    adb fastboot fsarchiver inxi pv rsync p7zip-full makeself zenity innoextract needrestart flatpak timeshift
    python3-defusedxml python3-packaging python3-pip python3-tqdm
    libayatana-appindicator3-1 gamemode vulkan-tools mangohud vkd3d-compiler goverlay winetricks
    gcc make cmake meson ninja-build
    gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly
    zsh zsh-syntax-highlighting zsh-autosuggestions
)
if ! sudo apt-get install -yq "${PACKAGES_INSTALL[@]}"; then
    FAILED_PACKAGES=()
    for pkg in "${PACKAGES_INSTALL[@]}"; do
        if ! sudo apt-get install -yq "$pkg" > /tmp/install-"$pkg".log 2>&1; then
            FAILED_PACKAGES+=("$pkg")
        fi
    done
fi

show_progress 5 $TOTAL_STEPS "$MSG_PHASE_2"

if command -v flatpak &>/dev/null; then
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
fi

add_ppa_and_install "atareao/telegram" telegram || true
add_ppa_and_install "zhangsongcui3371/fastfetch" fastfetch || true

if ! add_ppa_and_install "stebbins/handbrake-releases" handbrake handbrake-cli; then
    wait_for_apt
    sudo apt-get install -yq handbrake handbrake-cli || true
fi

add_ppa_and_install "cdemu/ppa" cdemu-daemon cdemu-client || true

sudo systemctl disable --now cdemu-daemon 2>/dev/null || true
sudo systemctl mask cdemu-daemon 2>/dev/null || true
mkdir -p "$HOME/.config/autostart"
for f in /etc/xdg/autostart/gcdemu.desktop /etc/xdg/autostart/cdemu.desktop /usr/share/applications/gcdemu.desktop; do
    if [[ -f "$f" ]]; then
        cp -f "$f" "$HOME/.config/autostart/$(basename "$f")"
        if grep -q '^Hidden=' "$HOME/.config/autostart/$(basename "$f")"; then
            sed -i 's/^Hidden=.*/Hidden=true/' "$HOME/.config/autostart/$(basename "$f")"
        else
            echo "Hidden=true" >> "$HOME/.config/autostart/$(basename "$f")"
        fi
    fi
done
pkill -f gcdemu 2>/dev/null || true

if command -v flatpak &>/dev/null; then
    sudo flatpak install -y flathub com.github.tchx84.Flatseal || true
fi

show_progress 6 $TOTAL_STEPS "$MSG_PHASE_2"

wait_for_apt
sudo apt-get install -yq wine wine64 || true

VGA_INFO=$(lspci -nn | grep -iE "VGA|3D|Display" || true)
MODULES_FILE="/etc/initramfs-tools/modules"
add_module() { grep -q "^$1" "$MODULES_FILE" || echo "$1" | sudo tee -a "$MODULES_FILE" > /dev/null; }

HAS_NVIDIA=0; HAS_AMD=0; HAS_INTEL=0
echo "$VGA_INFO" | grep -iq "NVIDIA" && HAS_NVIDIA=1
echo "$VGA_INFO" | grep -iq "AMD"    && HAS_AMD=1
echo "$VGA_INFO" | grep -iq "Intel"  && HAS_INTEL=1

wait_for_apt

if [[ "$HAS_AMD" -eq 1 || "$HAS_INTEL" -eq 1 || ( "$HAS_NVIDIA" -eq 0 && "$HAS_AMD" -eq 0 && "$HAS_INTEL" -eq 0 ) ]]; then
    sudo apt-get install -yq libgl1-mesa-dri:i386 mesa-vulkan-drivers:i386 || true
fi
[[ "$HAS_AMD" -eq 1 ]]   && add_module "amdgpu"
[[ "$HAS_INTEL" -eq 1 ]] && add_module "i915"

if [[ "$HAS_NVIDIA" -eq 1 ]]; then
    NVIDIA_BRANCH=$(dpkg -l 2>/dev/null | grep -oP '^ii\s+nvidia-driver-\K[0-9]+' | sort -un | tail -1)
    if [[ -n "$NVIDIA_BRANCH" ]]; then
        sudo apt-get install -yq "libnvidia-gl-${NVIDIA_BRANCH}:i386" || true
    fi
    add_module "nvidia"
    add_module "nvidia_modeset"
    add_module "nvidia_uvm"
    add_module "nvidia_drm"
fi

sudo update-initramfs -u || true
sudo flatpak install -y flathub it.mijorus.gearlever || true

wait_for_apt
sudo apt-get install -yq "linux-headers-$(uname -r)" || true

show_progress 7 $TOTAL_STEPS "$MSG_PHASE_2"

mkdir -p "$DEB_DIR"
download_deb() { wget -q --timeout=30 -O "$3" "$2" || rm -f "$3"; }
get_github_deb_url() { curl -sf "https://api.github.com/repos/${1}/releases/latest" | grep "browser_download_url.*${2}" | cut -d '"' -f 4 || true; }

download_deb "Discord" "https://discord.com/api/download?platform=linux&format=deb" "$DEB_DIR/discord.deb"
OPENCODE_URL=$(get_github_deb_url "sst/opencode" "opencode-desktop-linux-amd64\\.deb")
[[ -n "$OPENCODE_URL" ]] && download_deb "opencode-desktop" "$OPENCODE_URL" "$DEB_DIR/opencode-desktop.deb"
LSFG_URL=$(get_github_deb_url "YuriSizov/ls-fg" "ls-fg_.*deb")
LSFG_VK_URL=$(get_github_deb_url "YuriSizov/ls-fg-vk" "deb")

[[ -n "$LSFG_URL" ]] && download_deb "ls-fg" "$LSFG_URL" "$DEB_DIR/lsfg.deb"
[[ -n "$LSFG_VK_URL" ]] && download_deb "ls-fg-vk" "$LSFG_VK_URL" "$DEB_DIR/lsfg-vk.deb"

add_ppa_and_install "faugus/faugus-launcher" faugus-launcher || true

shopt -s nullglob
DEB_FILES=("$DEB_DIR"/*.deb)
if [[ ${#DEB_FILES[@]} -gt 0 ]]; then
    wait_for_apt
    for deb in "${DEB_FILES[@]}"; do
        sudo apt-get install -yq "$deb" || true
    done
fi
shopt -u nullglob
rm -rf "$DEB_DIR"

# ==========================================================
# 3. WIRTUALIZACJA, FIREWALL I ZSH
# ==========================================================
show_progress 8 $TOTAL_STEPS "$MSG_PHASE_3"

wait_for_apt
sudo apt-get install -yq virt-manager qemu-system qemu-utils libvirt-daemon-system libvirt-clients ovmf dnsmasq bluetooth bluez bluez-firmware bluez-tools ufw || true

if command -v dconf &>/dev/null; then
    dconf load /org/virt-manager/virt-manager/ <<'EOF'
[/]
manager-window-height=297
manager-window-width=478
xmleditor-enabled=true

[confirm]
delete-storage=false
forcepoweroff=false

[connections]
autoconnect=['qemu:///system']
uris=['qemu:///system']

[conns/qemu:system]
window-size=(800, 600)

[details]
show-toolbar=true

[new-vm]
cpu-default='host-passthrough'
firmware='uefi'
graphics-type='spice'
storage-format='raw'

[stats]
enable-disk-poll=true
enable-memory-poll=true
enable-net-poll=true

[vmlist-fields]
disk-usage=false
network-traffic=false

[vms/2a91721fef6c4249997ea19b01801825]
autoconnect=1
vm-window-size=(1280, 842)
EOF
else
    log_warn "Brak polecenia dconf – pomijam wczytanie ustawień virt-managera." "dconf command not found – skipping virt-manager settings import."
fi

for svc in libvirtd virtqemud; do
    if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        sudo systemctl enable --now "${svc}.service" || true
        break
    fi
done

if ! sudo virsh net-info default &>/dev/null; then
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
fi
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default || true

if command -v ufw &>/dev/null || [[ -x /usr/sbin/ufw ]]; then
    [[ -f /etc/default/ufw ]] && sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw || true
    sudo ufw --force reset || true
    sudo ufw default deny incoming || true
    sudo ufw default allow outgoing || true
    sudo ufw allow in  on virbr0 || true
    sudo ufw allow out on virbr0 || true
    sudo ufw allow from 192.168.122.0/24 || true
    if dpkg -s openssh-server &>/dev/null || [[ -x /usr/sbin/sshd ]] || systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        sudo ufw allow ssh || true
    fi
    sudo ufw --force enable || true
fi

for grp in libvirt libvirt-qemu kvm; do
    getent group "$grp" &>/dev/null && sudo usermod -aG "$grp" "$CURRENT_USER" || true
done

show_progress 9 $TOTAL_STEPS "$MSG_PHASE_3"

sudo systemctl enable fstrim.timer || true
sudo journalctl --vacuum-time=2d || true
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub || true
sudo update-grub || true

show_progress 10 $TOTAL_STEPS "$MSG_PHASE_3"

sudo mkdir -p /etc/NetworkManager/conf.d
echo -e "[main]\ndns=default\nrc-manager=symlink" | sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null
echo -e "[global-dns]\n\n[global-dns-domain-*]\nservers=1.1.1.1,1.0.0.1,2606:4700:4700::1112,2606:4700:4700::1002" | sudo tee /etc/NetworkManager/conf.d/global-dns.conf > /dev/null

ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -v "^lo" | head -n 1 | cut -d: -f1 || true)
if [[ -n "$ACTIVE_CONN" ]]; then
    if sudo nmcli connection modify "$ACTIVE_CONN" ipv4.dns "1.1.1.1,1.0.0.1" ipv6.dns "2606:4700:4700::1112,2606:4700:4700::1002"; then
        sudo nmcli connection up "$ACTIVE_CONN" || true
        for i in {1..10}; do
            getent hosts github.com &>/dev/null && break
            sleep 1
        done
    fi
fi

if command -v zsh &>/dev/null; then
    sudo chsh -s /usr/bin/zsh "$CURRENT_USER" || true
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
    fi
    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$P10K_DIR" ]]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" || true
    fi
    ZSHRC="$HOME/.zshrc"
    if [[ -f "$ZSHRC" ]]; then
        sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC" || true
        sed -i 's/^plugins=(.*/plugins=(git sudo systemd debian)/' "$ZSHRC" || true
        grep -q "LC_ALL=$SYSTEM_LOCALE" "$ZSHRC" || echo "export LC_ALL=$SYSTEM_LOCALE" >> "$ZSHRC"
        grep -q "^fastfetch"         "$ZSHRC" || echo "fastfetch"                  >> "$ZSHRC"
        grep -q "zsh-syntax-highlighting.zsh" "$ZSHRC" || echo "source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> "$ZSHRC"
        grep -q "zsh-autosuggestions.zsh"     "$ZSHRC" || echo "source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh"         >> "$ZSHRC"
    fi
fi

show_progress 11 $TOTAL_STEPS "$MSG_PHASE_3"

# ==========================================================
# 4. ZAKOŃCZENIE I SPRZĄTANIE
# ==========================================================
if [[ "$USE_RUN0" -eq 1 ]]; then
    sudo rm -f "$RUN0_NOPASSWD_FILE"
    sudo systemctl try-restart polkit 2>/dev/null || true
else
    sudo rm -f /etc/sudoers.d/99-temp-installer
fi

show_progress 12 $TOTAL_STEPS "$MSG_PHASE_4"
echo -e "\n" >&3

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}✔ CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

# ==========================================================
#  RESTART SYSTEMU
# ==========================================================
if [[ "$SCRIPT_LANG" == "pl" ]]; then
    RESTART_PROMPT="Czy chcesz teraz zrestartować system? [T/N]: "
else
    RESTART_PROMPT="Do you want to restart the system now? [Y/N]: "
fi
echo -en "${INFO}==> ${RESTART_PROMPT}${NC}" >&3
read -r RESTART_CHOICE < /dev/tty
case "$RESTART_CHOICE" in
    [YyTt]*)
        systemctl reboot
        ;;
    *)
        exit 0
        ;;
esac
