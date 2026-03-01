![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=for-the-badge&logo=gnu-bash)
![EndeavourOS](https://img.shields.io/badge/OS-EndeavourOS-7F3F98?style=for-the-badge&logo=endeavouros&logoColor=white)
![Arch Linux](https://img.shields.io/badge/OS-Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

**Tired of blindly running `pacman -Syu` and crossing your fingers that your system doesn't break?**

</div>

**Arch_Smart_Update** is an advanced, ultra-safe, and visually stunning bash script for managing system updates on Arch Linux and its derivatives (currently only EndeavourOS). It acts as an intelligent shield for your package manager: analyzing pending updates, checking official news, automating backups, and utilizing a built-in **Advisor** to protect your machine from Day-1 bugs, broken dependencies, and kernel panics.

---

![01](https://github.com/user-attachments/assets/9aab8143-8587-4c49-b822-915f9a1d950e)
![02](https://github.com/user-attachments/assets/bed32c77-38d2-4a8f-a017-35fc3099d786)

---

## ✨ Why You Need This Script (Key Features)

- **⚡ Safe RAM-Based Sync (`/tmp`):** The script never touches your live local pacman database during the checking phase. All database syncing and calculations are done in an isolated temporary directory in your RAM (`/tmp/checkupdates-db...`). This 100% prevents catastrophic "partial upgrade" scenarios if you decide to cancel the update.
- **🧠 Smart Update Advisor:** Automatically analyzes the criticality of pending packages. If a system-crashing update (like the Linux kernel, `glibc`, or NVIDIA drivers) was released less than 24 hours ago, the script strongly advises you to wait, ensuring upstream stability before you apply it.
- **📰 Arch News Integration (RSS):** Fetches the latest official Arch Linux news feed. If there’s a recent post requiring manual intervention, you'll get a bright warning before you press "Y".
- **🛡️ Automated Pacman DB Backups:** Automatically creates a `.tar.gz` backup of your `/var/lib/pacman/local` database before applying any changes. It keeps the last 5 copies so you can always roll back seamlessly.
- **🚀 Smart Mirror Management:** Monitors your mirrorlist age and sync speeds. If mirrors are older than 7 days or time out, it detects the instability and offers to automatically refresh them via `reflector` and `eos-rankmirrors`.
- **📊 Rich CLI Analytics:** Displays a beautifully formatted, color-coded terminal table showing update types (MAJOR, MINOR, PATCH, CALVER, EPOCH), package age in hours, download sizes, repositories, and descriptions.
- **🔒 Intelligent Lock File Removal:** Detects a stale `/var/lib/pacman/db.lck` file and uses `fuser` to check if a package manager is actually running. If it's a phantom lock, the script safely removes it for you.
- **🚨 IgnorePkg Conflict Checker:** If you have frozen packages via `pacman.conf`, the script simulates the update in the background and warns you of any dependency breakages caused by skipped packages.
- **🧩 Seamless Ecosystem Integration:** Full, native support for AUR helpers (`yay`, `paru`), as well as synergy with `eos-update` and `topgrade` to handle your Flatpaks, firmwares, and dotfiles.

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

---

## 📋 Dependencies

The script relies on standard system utilities, but make sure you have the following installed:

`sudo pacman -S python bash tar gawk coreutils psmisc`

## 🛠️ Installation

## Option 1: Install from AUR (Recommended)
The script is officially available in the Arch User Repository. You can install it using your favorite AUR helper:

For yay:  
`yay -S arch-smart-update`  
For paru:  
`paru -S arch-smart-update`

## Option 2: Manual Installation
If you prefer not to use the AUR, you can install the script manually:

`curl -O https://raw.githubusercontent.com/motorrin/Arch_Smart_Update/main/arch-smart-update`  
`chmod +x arch-smart-update`  
`mv arch-smart-update ~/arch-smart-update`  


## ❓ How do I use this script?
If you installed via AUR, the command is globally available as:  
`arch-smart-update`  
If you installed Manually, the command is:  
`~/arch-smart-update`

## Why write so many letters? Create an alias!

### 1. Check if you're using bash or zsh:
`echo $0`

### 2. Open your configuration file:
For bash:  
`nano ~/.bashrc`  
For zsh:  
`nano ~/.zshrc`

### 3. Add the alias to the very end of the file:
If you installed via AUR:  
`alias up="arch-smart-update"`  
If you installed Manually:  
`alias up="~/arch-smart-update"`

### 4. Apply the changes immediately:
For bash:  
`source ~/.bashrc`  
For zsh:  
`source ~/.zshrc`
