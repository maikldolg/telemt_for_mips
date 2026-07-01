Telemt 3.4.13
```bash
opkg install curl

cd /opt/tmp/
curl -L -O https://raw.githubusercontent.com/maikldolg/telemt_for_mips/refs/heads/main/install_telemt_v13.sh
sh install_telemt.sh
```
Telemt 3.4.18
```bash
opkg install curl

cd /opt/tmp/
curl -L -O https://raw.githubusercontent.com/maikldolg/telemt_for_mips/refs/heads/main/install_telemt_v18.sh
sh install_telemt.sh
```
Telemt-panel
```bash
cd /opt/tmp/
curl -L -O https://raw.githubusercontent.com/maikldolg/telemt_for_mips/refs/heads/main/install_telemt-panel.sh
sh install_telemt-panel.sh
```
эмуляция systemD для работы перезапуска через панель и логов
```bash
curl -L https://raw.githubusercontent.com/anch665/keendev/refs/heads/main/systemctl.sh -o /opt/usr/bin/systemctl
chmod +x /opt/usr/bin/systemctl
curl -L https://raw.githubusercontent.com/anch665/keendev/refs/heads/main/journalctl.sh -o /opt/usr/bin/journalctl
chmod +x /opt/usr/bin/journalctl
/opt/etc/init.d/S99telemt-panel restart
```
