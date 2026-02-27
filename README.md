# 🛡️ Smart Update Wrapper for EndeavourOS & Arch Linux

![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=for-the-badge&logo=gnu-bash)
![OS](https://img.shields.io/badge/OS-Arch_Linux_%7C_EndeavourOS-1793D1?style=for-the-badge&logo=arch-linux)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

An advanced, safe, and visually appealing bash script for managing system updates on **EndeavourOS** and **Arch Linux**.

Instead of blindly running `pacman -Syu`, this script analyzes pending updates, checks official news, creates backups, and utilizes an **Advisor** to protect your system from Day-1 bugs, kernel panics, and broken packages.

---

![01](https://github.com/user-attachments/assets/9aab8143-8587-4c49-b822-915f9a1d950e)
![02](https://github.com/user-attachments/assets/bed32c77-38d2-4a8f-a017-35fc3099d786)

---

## ✨ Key Features

* 🧠 **Smart Update Advisor**: Analyzes the criticality of pending packages. If a system-critical update (like the Linux kernel or NVIDIA drivers) was released less than 24 hours ago, the script advises you to wait to ensure stability.
* 📰 **Arch News Integration**: Fetches the latest official Arch Linux RSS feed. If there is a recent news post requiring manual intervention, the script will warn you before proceeding.
* 📦 **Safe RAM-based Sync**: Uses a temporary database in memory (`/tmp/checkupdates-db...`) to calculate updates without touching your local sync DB, completely preventing partial upgrade scenarios.
* 🛡️ **Automated Pacman DB Backup**: Automatically creates a `.tar.gz` backup of `/var/lib/pacman/local` before applying any changes, keeping the last 5 copies.
* 🚀 **Smart Mirror Management**: Automatically detects old or failing mirrors and offers to refresh them using `reflector` or `eos-rankmirrors`.
* 📊 **Rich CLI Analytics**: Displays a beautifully formatted, color-coded table showing update types (MAJOR, MINOR, PATCH, EPOCH), package age, download sizes, and descriptions.
* 🧩 **AUR & Helper Integration**: Full support for AUR helpers (`yay`, `paru`), as well as native integration with `eos-update` and `topgrade`.
* 🚨 **IgnorePkg Conflict Checker**: Smartly simulates the update to warn you about dependency breakages if you have skipped specific packages via `pacman.conf`.

## ⚙️ Package Categorization & Threat Levels

The script divides packages into four categories and calculates a safe waiting period before updating:

- ☢️ **NUKE (System Core)**: *glibc, linux, nvidia, systemd*.  
  **Recommendation:** Wait **24 hours** after release to avoid critical system breakage.
- ❗ **CRIT (Crucial Drivers & Services)**: *mesa, xorg, wayland, dbus*.  
  **Recommendation:** Wait **12 hours**.
- ⭐ **FEAT (Desktop Environments)**: *KDE, GNOME, Hyprland, Sway*.  
  **Recommendation:** Wait **6 hours**.
- 📦 **Standard Packages & AUR**:  
  **Recommendation:** Wait **3 hours** (to allow global mirrors to fully sync).

## 🛠️ Setup

**1. Create the script file and paste the code:**  
`nano ~/EndeavourOS_Smart_Update_Wrapper`  

**2. Make the script executable:**  
`chmod +x ~/EndeavourOS_Smart_Update_Wrapper`  

**3. Check if you are using bash or zsh:**  
`echo $0`  

**4. Open the bash/zsh configuration file:**  

**for bash:**  
`nano ~/.bashrc`  

**for zsh:**  
`nano ~/.zshrc`  

**5. Add the following alias to the end of the file:**  
`alias up="~/EndeavourOS_Smart_Update_Wrapper"`  

**6. Apply the changes immediately:**  

**for bash:**  
`source ~/.bashrc`  

**for zsh:**  
`source ~/.zshrc`  

**7. Run the script using the new alias:**  
`up`  
