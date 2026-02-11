# ❗ Compatibility Warning

This script is specifically tuned for **EndeavourOS** running the **KDE Plasma** Desktop Environment.

While the core update logic works on any Arch-based system, the **Critical Package List** (`CRITICAL_PKGS`) and **Reboot Detection** logic are optimized for:
*   **OS:** EndeavourOS
*   **DE:** KDE Plasma 6 (Qt 6, Wayland)
*   **GPU:** Nvidia (Proprietary/Open) & AMD (Mesa)
*   **Shell:** Bash

*If you use GNOME, Hyprland, or a different setup, you may need to adjust the package lists in the script.*

---

# 🛡️ EndeavourOS Smart Update Wrapper

A robust Bash script designed to make EndeavourOS updates safer and more informative. It analyzes pending updates before installation, highlights critical system components, and checks for official Arch Linux news.

# ✨ Key Features

# 1. 🔒 Safe Database Sync (Sandboxing)
The script performs pacman -Sy into a temporary directory instead of the system database.
•  Prevents "partial upgrade" states if the update is cancelled.
•  Allows checking for updates safely without touching the live pacman DB.

# 2. 📰 Arch News Integration

Checks the official Arch Linux News feed before syncing databases.
•  Alerts you to news items from the last 14 days to ensure you don't miss manual intervention notices.
•  Acts as a safeguard against "blind" updates that could break the system.

# 3. 🧠 Semantic Version Analysis

Instead of just showing version numbers, the script calculates the type of update:
🔴 MAJOR / EPOCH: Breaking changes (e.g., 1.x → 2.x).
🔵 MINOR / CALVER: New features.
⚪ Patch: Bug fixes.

# 4. 🎯 Critical Package Highlighting

Includes a curated list of critical packages (Kernel, Nvidia, Glibc, Systemd, Mesa, KDE/Qt, etc.).
•  These are tagged as CORE or CRIT.
•  Highlighted with distinct backgrounds to catch your eye immediately.

# 5. 🔄 Reboot Detector

Smart heuristics to determine if a reboot is needed. It scans for updates to:
•  Linux Kernels / Microcode
•  Nvidia / Mesa drivers
•  Systemd / Glibc / D-Bus
•  Desktop Environment stack (Wayland, Plasma, Qt5/6)
    ...and issues a warning: ⚠ Kernel/Core update detected. Reboot will be required!.

# 6. 🚀 Workflow Integration

•  Designed for EndeavourOS (uses eos-update) but falls back to standard pacman.
•  Optional integration with Topgrade to handle Flatpaks, AUR, and firmware updates after the core system update.

# 📦 Requirements
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
