<!-- ABOUT THE PROJECT -->
## About The Project

<!-- [![Product Name Screen Shot][product-screenshot]](https://example.com) -->

Post-installation script to transform a Fedora Netinstall (minimal) into a ready-to-use:

* KDE Plasma desktop (Wayland)

* Gaming-ready system

* Multimedia-enabled workstation

* Developer-friendly environment

With the help of [Not Another 'Things To Do'!](https://nattdf.streamlit.app/)

I've made this script **for me and my own computer** but it may be useful for those who have a full AMD configuration too.

### Built With

* 🖊️ Bash

### What It Does

The script:

* Updates the system
* Enables RPM Fusion (free + nonfree)
* Installs multimedia codecs (ffmpeg + freeworld)
* Installs KDE Plasma + SDDM
* Configures graphical target
* Installs gaming stack (Steam, Heroic, GameMode, MangoHud…)
* Installs essential applications _(for me of course)_
* Configures tuned (performance profile)
* Sets up Flatpak + Flathub

### Complete list of features

#### Desktop

* KDE Plasma (Wayland)
* SDDM display manager
* Graphical target enabled

#### Gaming Sofware

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

<!-- GETTING STARTED -->
## Getting Started

To get a local copy up and running follow these simple steps.

### Prerequisites

* [Fedora Netinstall - Everything](https://www.fedoraproject.org/misc#everything)
* Non-root user created **but must be sudoers**
* Internet connection
* Change the hostname in the script and put whathever software you need

### Installation
 
1. Complete the NetInstall with your own parameters (disk configuration, user creation, ... **BUT** you should net the software selection with only **Fedora Custom Operating System** and nothing else)
2. When initial configuration and installation is finished, you'll boot in TTY
3. You must do :
```
curl -fsSLO https://raw.githubusercontent.com/Fleorens/Fedora-AutoInstall/main/postinstall.sh
chmod +x postinstall.sh
sudo ./postinstall.sh
```
4. Then, you wait. If you're prompted to reboot due to firmware upgrade or anything else, you can and then relaunch the script.
5. When finished, you'll be ask to reboot.
6. Enjoy


<!-- USAGE EXAMPLES -->
## Security Notice

Always:

* Review the script before execution
* Verify repository URL
* Avoid running unknown remote scripts