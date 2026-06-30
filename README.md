Уставновка telemt и telemt-panel на entware keenetic (только Mips)

```bash
opkg install curl

cd /opt/tmp/
curl -L -O https://raw.githubusercontent.com/maikldolg/telemt_for_mips/refs/heads/main/install_telemt.sh
sh install_telemt.sh
```
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
