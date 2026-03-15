![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=for-the-badge&logo=gnu-bash)
![CachyOS](https://img.shields.io/badge/OS-CachyOS-008B8B?style=for-the-badge&logo=linux&logoColor=white)
![EndeavourOS](https://img.shields.io/badge/OS-EndeavourOS-7F3F98?style=for-the-badge&logo=endeavouros&logoColor=white)
![Arch Linux](https://img.shields.io/badge/OS-Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

**Tired of blindly running `pacman -Syu` and crossing your fingers that your system doesn't break?**

</div>

**Arch_Smart_Update** is an advanced, ultra-safe, and visually stunning bash script for managing system updates on vanilla **Arch Linux** and its derivatives (has better integration with **EndeavourOS** and **CachyOS** packages and tools, **but works great on other Arch-based distributions as well**). It acts as an intelligent shield for your package manager: analyzing pending updates, checking official news, automating backups, and utilizing a built-in **Advisor** to protect your machine from Day-1 bugs, broken dependencies, and kernel panics.

⚠️ **IMPORTANT DISCLAIMER:** The update recommendations provided by the Advisor are helpful guidelines, not absolute rules. As an Arch Linux user, **you are the system administrator** and hold ultimate responsibility for your machine. Always review the update list and use your own judgment before pressing "Y". This script is a powerful safety net, but it does not replace common sense. The author is not responsible for any broken systems, unbootable kernels, or data loss!

---

![01](https://github.com/user-attachments/assets/9aab8143-8587-4c49-b822-915f9a1d950e)
![02](https://github.com/user-attachments/assets/bed32c77-38d2-4a8f-a017-35fc3099d786)

---

## ✨ Why You Need This Script (Key Features)

- **⚡ Safe RAM-Based Sync (`/tmp`):** The script never touches your live local pacman database during the checking phase. All database syncing and calculations are done in an isolated temporary directory in your RAM (`/tmp/checkupdates-db...`). This 100% prevents catastrophic "partial upgrade" scenarios if you decide to cancel the update.
- **🧠 Smart Update Advisor:** Automatically analyzes the criticality of pending packages. If a system-crashing update (like the Linux kernel, `glibc`, or NVIDIA drivers) was released less than 24 hours ago, the script strongly advises you to wait, ensuring upstream stability before you apply it.
- **📰 Arch News Integration (RSS):** Fetches the latest official Arch Linux news feed. If there’s a recent post requiring manual intervention, you'll get a bright warning before you press "Y".
- **🛡️ Automated Pacman DB Backups:** Automatically creates a `.tar.gz` backup of your `/var/lib/pacman/local` database before applying any changes. It keeps the last 5 copies so you can always roll back seamlessly.
- **🚀 Smart Mirror Management:** Monitors your mirrorlist age and sync speeds. If mirrors are older than 7 days or time out, it detects the instability and offers to automatically refresh them via `reflector`, `eos-rankmirrors`, or `cachyos-rate-mirrors`.
- **📊 Rich CLI Analytics:** Displays a beautifully formatted, color-coded terminal table showing update types (MAJOR, MINOR, PATCH, CALVER, EPOCH), package age in hours, download sizes, repositories, and descriptions.
- **🔒 Intelligent Lock File Removal:** Detects a stale `/var/lib/pacman/db.lck` file and uses `fuser` to check if a package manager is actually running. If it's a phantom lock, the script safely removes it for you.
- **🚨 IgnorePkg Conflict Checker:** If you have frozen packages via `pacman.conf`, the script simulates the update in the background and warns you of any dependency breakages caused by skipped packages.
- **🧩 Seamless Ecosystem Integration:** Full, native support for AUR helpers (`yay`, `paru`), as well as synergy with `eos-update` and `topgrade` to handle your Flatpaks, firmwares, and dotfiles.
- **👻 Background Daemon & Notifications:** You can allow the script to run in the background using a user systemd timer. It silently checks for updates using `fakeroot` (no sudo required) and sends desktop notifications via `libnotify` when safe updates are ready or critical Arch News drops.
- **🎛️ Unified Configuration Management:** All custom commands, mirror overrides, behavior settings, and user package arrays are securely parsed from a single `settings.conf` file. Your personal settings are isolated from upstream defaults and will never be overwritten during script updates.

---

## ⚙️ Package Categorization & Threat Levels

The script recognizes hundreds of packages (from DEs to base system components) and categorizes them into four threat levels, calculating a safe "cooldown" period:

- **☢️ NUKE (System Core):** `glibc`, `linux`, `nvidia`, `systemd`, `grub`, `cryptsetup`.
  > *Recommendation:* Wait **24 hours**.
- **❗ CRIT & DEs (Crucial Services & Desktop Environments):** `mesa`, `wayland`, `dbus`, `KDE Plasma`, `GNOME`, `Hyprland`, etc.
  > *Recommendation:* Wait **12 hours**.
- **⭐ FEAT (General Features & Utilities):** Audio/Network stacks, Frameworks, EOS apps.
  > *Recommendation:* Wait **6 hours**.
- **📦 Standard Packages & AUR:**
  > *Recommendation:* Wait **3 hours**.
- **💡 Customizing the lists:** You don't have to wait for an update to add your specific apps to these categories! You can easily append your own packages to the NUKE, CRIT, or FEAT lists using the user_packages.conf file, and your changes will survive all future script updates.

---

## 📁 Configuration & Customization

On its first run, the script creates a configuration folder at `~/.config/arch-smart-update/`, downloads the latest default templates from GitHub, and asks if you prefer to be prompted for mirror ranking before updates.

To ensure your personal settings are never overwritten by script updates, the configuration is split into two types:

**1. Developer Managed (Auto-updating via GitHub):**
- `packages.conf` — The master list of categorized packages.
- `*.default.conf` — Templates showing the latest recommended syntax.

**2. User Managed (Safe from overwrites):**
- `settings.conf` — Your master configuration file. Here you can configure:
  - **General Settings:** `PROMPT_MIRROR_REFRESH`, `MAX_BACKUP_COPIES`, `AUR_HELPER_OVERRIDE`.
  - **Daemon & Logging:** Configure `ENABLE_BACKGROUND_CHECK`, systemd timer intervals, and `GENERATE_LOGS`.
  - **Overrides:** Define a `CUSTOM_REFLECTOR_CMD` or define `CUSTOM_CMDS` (e.g., `flatpak update -y`) to run instead of the standard utilities.
  - **User Packages:** Add your own apps to the arrays (e.g., `USER_CRITICAL_PKGS=("my-important-app")`) to integrate them into the Advisor's threat levels.

*(Note: If you are upgrading from a pre-3.0 version, the script features an automated migration tool that will seamlessly merge your old fragmented files into the new `settings.conf` on its first run).*

Whenever the master configuration on GitHub is updated, the script will quietly pull the changes without touching your custom files!

## 📋 Dependencies

The script relies on standard system utilities, but make sure you have the following packages installed:

`sudo pacman -S curl python bash tar gawk coreutils psmisc`

*(Note: The `python` package provides `python3` for the Arch News RSS check, and `psmisc` provides the `fuser` command required for smart lock file management).*

**Optional Dependencies:**
- `base-devel` (specifically `fakeroot`) — Required for the background daemon to sync databases without sudo privileges.
- `libnotify` — Required for desktop notifications in daemon mode.

## 🛠️ Installation

## Option 1: Install from AUR (Recommended)
The script is officially available in the Arch User Repository. You can install it using your favorite AUR helper:

For yay:  
`yay -S arch-smart-update`  
For paru:  
`paru -S arch-smart-update`

## Option 2: Manual Installation
If you prefer not to use the AUR, you can install the script manually:

1. `cd ~`  
2. `curl -O https://raw.githubusercontent.com/motorrin/Arch_Smart_Update/main/arch-smart-update`  
3. `chmod +x arch-smart-update`

## ❓ How do I use this script?

If you installed via AUR, the command is globally available as:  
`arch-smart-update`

If you installed Manually, the command is:  
`~/arch-smart-update`

## ⌨️ Why write so many letters? Create an alias!

### 1. Check which shell you are using:
`echo $SHELL`

### 2. Open your configuration file:
For bash:  
`nano ~/.bashrc`  
For zsh:  
`nano ~/.zshrc`  
For fish:  
`nano ~/.config/fish/config.fish`

### 3. Add the alias to the very end of the file:

If you installed via AUR:  
`alias up="arch-smart-update"`

If you installed Manually:  
`alias up="$HOME/arch-smart-update"`

### 4. Apply the changes immediately:

For bash:  
`source ~/.bashrc`  
For zsh:  
`source ~/.zshrc`  
For fish:  
`source ~/.config/fish/config.fish`

## 🗑️ Uninstalling the Daemon

If you decide to remove arch-smart-update and want to ensure no background tasks are left behind, please run these commands:

1. Disable and stop the background timer:  
`systemctl --user disable --now arch-smart-update.timer`

2. Remove the systemd unit files:  
`rm -f ~/.config/systemd/user/arch-smart-update.*`

3. Reload systemd manager:  
`systemctl --user daemon-reload`
