# 🌿 Linux Mint Post-Install Setup Script

A comprehensive, automated Bash post-installation script for **Linux Mint**. It configures APT repositories (including `universe`/`multiverse` and several third-party sources), self-heals broken/unreachable APT sources, detects your GPU and installs matching drivers/32-bit libraries, installs a large curated set of system/multimedia/gaming packages via APT/PPAs/Flatpak/standalone `.deb` files, configures virtualization (libvirt/QEMU) and the firewall, tweaks the GRUB timeout, and sets up Zsh with Oh My Zsh and Powerlevel10k.

The script auto-detects the system language (Polish/English) from the `LANG`/`LC_ALL` locale, and separately detects the best available system **locale** (falling back to `en_US.UTF-8` if the detected one isn't installed) for later Zsh configuration.

---

## 🚀 Script Features

- **Temporary Passwordless Sudo**: Requests the admin password once at the start, then configures a temporary `NOPASSWD` rule (via `/etc/sudoers.d/`, or a `polkit`/`run0` rule on systems without `visudo`) so the rest of the script can run unattended. The rule is automatically removed at the end.
- **`wait_for_apt` Locking Helper**: Stops PackageKit and waits for any existing APT/dpkg locks to clear before every package operation.
- **Self-Healing APT Updates (`safe_apt_update`)**: Runs `apt-get update`, and if it fails, parses the error output (in several languages) for the broken repository URLs, removes the matching `sources.list.d` entries automatically, and retries the update — so one bad third-party repo doesn't block the whole script.
- **APT Repository Setup**: Comments out the CD-ROM source, enables the `i386` architecture, enables the `universe`/`multiverse` components, and adds the official **Google Chrome** and **Brave Browser** APT repositories with their signing keys (Brave's key import is verified before the repo is actually added).
- **`add_ppa_and_install` Helper**: Adds a PPA, updates, and installs the given packages; if the install fails, it automatically removes the PPA again and refreshes APT, so a broken PPA doesn't leave the system in a bad repo state. Used for Telegram, Fastfetch, HandBrake (with a direct-package fallback), and CDEmu.
- **Package Installation**: Installs a large curated `PACKAGES_INSTALL` set covering browsers (Chrome, Brave), media/creative apps (GIMP, Kdenlive, Mixxx, SoundConverter...), dev tools (`gcc`, `cmake`, `meson`, `ninja-build`, `build-essential`...), and the gaming stack (`gamemode`, `mangohud`, `vkd3d-compiler`, `goverlay`, `winetricks`, `vulkan-tools`) — falling back to installing packages one-by-one (with per-package logs) if the bulk install fails.
- **GPU Detection & Driver Setup**: Detects NVIDIA/AMD/Intel GPUs via `lspci`, installs matching 32-bit Mesa/Vulkan libraries (or the matching `libnvidia-gl-<branch>:i386` package, auto-detected from the installed NVIDIA driver version), adds the right kernel modules to `/etc/initramfs-tools/modules`, installs matching Linux kernel headers, and rebuilds the initramfs.
- **Flatpak & Standalone `.deb` Packages**: Adds the Flathub remote and installs Flatseal + Gear Lever; downloads and installs Discord and `ls-fg`/`ls-fg-vk` directly as `.deb` files (Discord from its official download endpoint, the others via the GitHub Releases API); installs Faugus Launcher via its PPA.
- **Virtualization & Firewall**: Installs `virt-manager`, `qemu-system`, `libvirt-daemon-system`, `ovmf`, and related tools; imports default `virt-manager` GUI preferences via `dconf load`; enables `libvirtd`/`virtqemud`; defines/starts/autostarts the default libvirt NAT network; resets and configures **UFW** (deny incoming by default, allow `virbr0` traffic and the libvirt subnet, and allow SSH only if an SSH server is actually detected running); adds the user to the `libvirt`/`libvirt-qemu`/`kvm` groups.
- **System Tuning & DNS**: Sets `GRUB_TIMEOUT=0` and regenerates the GRUB config; enables `fstrim.timer`; vacuums the journal to 2 days; sets Cloudflare (`1.1.1.2`/`1.0.0.2` + IPv6) as the system and NetworkManager DNS, applies it to the active connection, and waits (up to 10s) for DNS resolution to confirm connectivity before continuing.
- **Shell Setup**: If `zsh` is available, sets it as the default shell, installs Oh My Zsh (unattended) and the Powerlevel10k theme, and updates `~/.zshrc` (theme, plugins, the detected system locale, `fastfetch` on login, syntax-highlighting/autosuggestions sourcing).
- **Dotfiles & Config Copy**: Copies an optional `.update.sh` helper script plus `.local`/`.config` directories from the script folder into the user's home directory.
- **Progress Bar & Logging**: Displays a live progress bar across 4 phases / 12 steps. On failure, a detailed log is saved to `~/install_error_<timestamp>.log`.
- **Optional Reboot Prompt**: Asks **"Do you want to restart the system now? [Y/N]"** at the end instead of forcing a reboot.

---

## 🔍 Module Details

### 1. Preparation & Repositories
Copies dotfiles, grants temporary `NOPASSWD` sudo, enables `i386`/`universe`/`multiverse`, adds the Google Chrome and Brave repositories (with key verification), runs a self-healing `apt-get update` + upgrade, and installs `linux-firmware`.

### 2. Package & Flatpak Installation
Installs the curated system package set (falling back to per-package installation on bulk failure), sets up Flathub, and installs Telegram, Fastfetch, HandBrake, and CDEmu via their respective PPAs (each with automatic rollback on failure).

### 3. GPU Drivers & Standalone Packages
Detects the GPU vendor(s), installs matching 32-bit driver packages and kernel modules, rebuilds the initramfs, installs matching kernel headers, then downloads and installs Discord/`ls-fg`/`ls-fg-vk` as standalone `.deb`s and Faugus Launcher via PPA.

### 4. Virtualization, Firewall, GRUB & DNS
Installs and configures `virt-manager`/QEMU/libvirt with a default NAT network and imported GUI preferences, locks down the firewall with UFW while allowing libvirt traffic (and SSH only if a server is running), sets a zero-second GRUB timeout, and configures + verifies Cloudflare DNS.

### 5. Shell & Finalization
Sets up Zsh + Oh My Zsh + Powerlevel10k (if `zsh` is present) using the detected system locale, removes the temporary sudo/polkit rule, and prompts the user to reboot immediately or exit without rebooting.

---

🚀 How to Run

1: Clone the repository or download the files
```bash
git clone https://github.com/syscore88/mint-config.git
```

2: Enter the downloaded folder
```bash
cd mint-config
```

3: Make the script executable
```bash
chmod +x install.sh
```
4. Run the script
⚠️ **IMPORTANT:** Run the script as a **regular user** (NOT as root/sudo). The script will ask for the administrator password at the start to configure              temporary elevated privileges.
```bash
./install.sh
```
---

### ☕ Support the Project

If you find this tool helpful and it saved you some time, consider buying me a coffee to support further development! 

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/bartekszczecinski)

---

If you find this project useful, leave a star! ⭐

---

## ⚠️ Requirements & Notes

- A base **Linux Mint** installation with `apt` and an internet connection (packages come from the official repos, several PPAs, Google/Brave repos, Flathub, and GitHub releases).
- `sudo` access for the current user.
- The following optional files, placed alongside `install.sh`, are picked up automatically if present: `.update.sh`, `.local/`, `.config/`.
- Unlike some sibling scripts in this family, this version does **not** remove any pre-installed bloatware apps (`PACKAGES_REMOVE` is empty) and does **not** set a Plymouth boot-splash theme — it only adjusts the GRUB timeout.
- The script **installs a large number of packages** across several PPAs and **modifies the firewall to deny incoming traffic by default** — review `PACKAGES_INSTALL` and the UFW rules before running if that doesn't match your needs.
- On failure, check the generated `install_error_<timestamp>.log` file in your home directory for details.
