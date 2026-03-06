## About The Project

Post-installation script to transform a Fedora Netinstall (minimal) into a ready-to-use:

* KDE Plasma desktop (Wayland)
* Gaming-ready system
* Multimedia-enabled workstation
* Developer-friendly environment

With the help of [Not Another 'Things To Do'!](https://nattdf.streamlit.app/)

I've made this script **for me and my own computer** but it may be useful for those who have a full AMD configuration too.

### Built With

* Bash

### How It Works

The script is **modular and interactive**. On launch, you choose which modules to install:

| Module | Description | Required |
|--------|-------------|----------|
| **System Base** | System upgrade, hostname, base tools | Always |
| **DNF Config** | Parallel downloads, automatic updates | Always |
| **Multimedia** | RPM Fusion, ffmpeg, AMD HW codecs | Optional |
| **KDE Plasma** | KDE desktop + SDDM (Wayland) | Optional |
| **Flatpak** | Flatpak + Flathub repository | Optional |
| **Firmware** | Firmware updates via fwupd | Optional |
| **Virtualization** | libvirt, qemu | Optional |
| **Gaming** | Steam, Heroic, MangoHud, GameMode... | Optional |
| **Dev Tools** | VS Code, GitHub Desktop, git, htop... | Optional |
| **Applications** | Chromium, Thunderbird, Discord, VLC... | Optional |

Some modules (Gaming, Dev Tools, Applications) also ask individually for each application, so you can pick exactly what you need.

### Complete list of available software

#### Desktop

* KDE Plasma (Wayland)
* SDDM display manager
* Graphical target enabled

#### Gaming Software

* Steam
* Heroic Games Launcher
* ProtonUp-Qt
* MangoHud
* GameMode
* Gamescope
* vkBasalt
* tuned (performance profile)
* Vulkan tools

#### Multimedia

* RPM Fusion (free + nonfree)
* FFmpeg full build
* Mesa freeworld codecs
* GStreamer multimedia group

#### Tools

* Git
* Curl
* VS Code
* GitHub Desktop
* htop
* wget

#### Applications

* Chromium
* Thunderbird
* Discord
* LibreOffice (Flatpak)
* VLC
* RustDesk

## Getting Started

### Prerequisites

* [Fedora Netinstall - Everything](https://www.fedoraproject.org/misc#everything)
* Non-root user created **but must be sudoers**
* Internet connection
* (Optional) Change the `HOSTNAME` variable at the top of the script

### Installation

1. Complete the NetInstall with your own parameters (disk configuration, user creation, ... **BUT** you should set the software selection with only **Fedora Custom Operating System** and nothing else)
2. When initial configuration and installation is finished, you'll boot in TTY
3. Run:
```
curl -fsSLO https://raw.githubusercontent.com/Fleorens/Fedora-AutoInstall/main/postinstall.sh
chmod +x postinstall.sh
sudo ./postinstall.sh
```
4. The script will present a module selection menu. Choose what you need.
5. Within some modules (Gaming, Dev Tools, Apps), you'll be asked for each application individually.
6. If you're prompted to reboot due to firmware upgrade, you can and then relaunch the script.
7. When finished, you'll be asked to reboot.

## Security Notice

Always:

* Review the script before execution
* Verify repository URL
* Avoid running unknown remote scripts
