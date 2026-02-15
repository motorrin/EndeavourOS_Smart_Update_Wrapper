# 🛡️ EndeavourOS Smart Update Wrapper

A robust Bash script designed to make EndeavourOS (and Arch Linux) updates safer, more informative, and visually distinct. It analyzes pending updates before installation, highlights an extensive list of critical system components and Desktop Environments, and checks for official Arch Linux news.

# ✨ Key Features

# 1. 🔒 Safe Database Sync (Sandboxing)
The script performs pacman -Sy into a temporary directory instead of the system database.
•  Prevents "partial upgrade" states if the update is cancelled.
•  Allows checking for updates safely without touching the live pacman DB.

# 2. 📰 Arch News Integration

Checks the official Arch Linux News feed before syncing databases.
•  Warns you of news items from the last 14 days.
•  Acts as a safeguard against "blind" updates that could break the system.

# 3. 👓 Update Advisor

The algorithm will examine the list of updates for you. Not sure when to upgrade? We will help you decide.
• Applies different safety margins based on package impact: 12h for DEs/Kernels, 6h for Features/Drivers, 3h for Mirror sync status.
• Calculates exactly when the update becomes safe (e.g., "Better update at 21:45 (+1h 12m)").
• Prioritizes warnings (Critical > Feature > Mirror) to clearly explain why you should wait.

# 4. 🧠 Semantic Version Analysis

Instead of just showing version numbers, the script calculates the type of update:
🔴 MAJOR / EPOCH: Breaking changes (e.g., 1.x → 2.x).
🔵 MINOR / CALVER: New features.
⚪ Patch: Bug fixes.

# 5. 🎯 Critical Package Highlighting

The script now monitors a massive list of system-critical packages.
If any of these are in the update list, they are highlighted with a Red (CRIT) or Dark Gray (CORE) background.
Covered Categories:
•  Kernels: Linux (Stable, LTS, Zen, Hardened) & Firmware.
•  Drivers: NVIDIA (Proprietary/Open/DKMS), AMD (Mesa/Vulkan/ROCm), Intel (Media/Compute).
•  Base System: Systemd, Glibc, Grub, Cryptsetup, LLVM, Pacman/Keyrings.
•  Audio & Net: Pipewire, Wireplumber, NetworkManager, Bluez.
•  Desktop Environments: KDE Plasma, GNOME, XFCE, LXQt, Cinnamon, MATE, COSMIC (Epoch).
•  Window Managers: Hyprland, Sway, i3, Labwc, Qtile, Niri, Openbox.

# 6. 🔄 Reboot Detector

Uses heuristics to determine if the specific updates usually require a system restart. It scans for updates to:
•  Core: Kernels, Microcode, Systemd, Glibc, D-Bus, Cryptsetup.
•  Graphics: NVIDIA drivers, Mesa stack, Wayland/Xorg servers.
•  DE Frameworks: Qt5/Qt6 base, Plasma workspace, KWin.
•  Warning: Displays ⚠ Kernel/Core/DE update detected. Reboot will be required! to prevent running the system in an unstable state.

# 7. 🚀 Workflow Integration

•  EndeavourOS Native: Defaults to eos-update for the actual installation process.
•  Arch Compatible: Falls back to sudo pacman -Syu if EOS tools are missing.
•  Topgrade Support: Optional integration with topgrade to handle Flatpaks, AUR, and firmware updates automatically after the core system update.
•  Backup: Automatically creates a backup of the pacman local database before applying updates.

# 📦 Requirements
•  bash
•  pacman
•  curl
•  awk
•  python
•  (Optional) reflector
•  (Optional) eos-update (EndeavourOS utils)
•  (Optional) topgrade

# 🛠️ Installation & Setup

# 1. Create the script file and paste the code
nano ~/EOS-up

# 2. Make the script executable
chmod +x ~/EOS-up

# 3. Make sure that your system uses bash:
echo $0

# 4. Open the bash configuration file:
nano ~/.bashrc

# 5. Add the following alias to the end of the file:
alias up="~/EOS-up"

# 6. Apply the changes immediately:
source ~/.bashrc

# 7. Run the script using the new alias:
up
