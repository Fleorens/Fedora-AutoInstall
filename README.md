# Fedora-AutoInstall

## After Fedora netinstall (minimal)

```bash
sudo dnf -y install curl ca-certificates
curl -fsSLO https://raw.githubusercontent.com/<USER>/<REPO>/main/postinstall.sh
chmod +x postinstall.sh
sudo ./postinstall.sh
```

## After Fedora netinstall (minimal)

Updates system
Enables RPM Fusion + codecs
Installs KDE Plasma + SDDM (Wayland)
Installs apps (Steam, Heroic, VSCode, Discord, etc.)
Gaming/perf stack (GameMode, MangoHud, gamescope, tuned)
