Уставновка telemt и telemt-panel на entware keenetic (только aarch64)
```bash
opkg update
opkg install curl
opkg install libnghttp2
```
```bash
curl -L https://raw.githubusercontent.com/augin/telemt_script/refs/heads/main/installer_telemt_v2.sh -o /opt/tmp/install_telemt.sh
sh /opt/tmp/install_telemt.sh
```
```bash
curl -L https://raw.githubusercontent.com/augin/telemt_script/refs/heads/main/install_telemt-panel.sh -o /opt/tmp/install_telemt-panel.sh
sh /opt/tmp/install_telemt-panel.sh
```
эмуляция systemD для работы перезапуска через панель и логов
```bash
curl -L https://raw.githubusercontent.com/anch665/keendev/refs/heads/main/systemctl.sh -o /opt/usr/bin/systemctl
chmod +x /opt/usr/bin/systemctl
curl -L https://raw.githubusercontent.com/anch665/keendev/refs/heads/main/journalctl.sh -o /opt/usr/bin/journalctl
chmod +x /opt/usr/bin/journalctl
/opt/etc/init.d/S99telemt-panel restart
```
