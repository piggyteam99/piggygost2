#!/bin/bash

# ==========================================
# Gost Bandwidth Aggregation Tunnel
# FINAL FIXED VERSION (Relay+MWS)
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}لطفا با دسترسی Root اجرا کنید.${NC}"
  exit
fi

# ==========================================
# Install Gost
# ==========================================

install_prerequisites() {

    clear
    echo -e "${CYAN}در حال نصب gost ...${NC}"

    apt-get update -y
    apt-get install -y wget curl ufw

    systemctl stop gost 2>/dev/null

    rm -f /usr/local/bin/gost

    wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz -O gost.gz

    gzip -d gost.gz

    mv gost /usr/local/bin/gost

    chmod +x /usr/local/bin/gost

    echo -e "${GREEN}Gost نصب شد ✔${NC}"

    sleep 2
}

# ==========================================
# IRAN SERVER SETUP
# ==========================================

setup_iran_tunnel() {

    clear

    echo -e "${CYAN}تنظیم سرور ایران${NC}"

    read -p "پورت ورودی ایران: " LOCAL_PORT

    read -p "IP سرور خارج: " FOREIGN_IP

    read -p "شروع رنج پورت خارج: " RANGE_START

    read -p "پایان رنج پورت خارج: " RANGE_END

    SERVICE_NAME="gost-ir-${LOCAL_PORT}.service"

cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Iran Aggregation Tunnel
After=network.target

[Service]
Type=simple

ExecStart=/usr/local/bin/gost \
-L tcp://0.0.0.0:${LOCAL_PORT} \
-F relay+mws://${FOREIGN_IP}:${RANGE_START}-${RANGE_END}

Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    systemctl enable ${SERVICE_NAME}

    systemctl restart ${SERVICE_NAME}

    ufw allow ${LOCAL_PORT}/tcp >/dev/null 2>&1

    sleep 1

    if systemctl is-active --quiet ${SERVICE_NAME}; then

        echo -e "${GREEN}تانل ایران با موفقیت فعال شد ✔${NC}"

    else

        echo -e "${RED}خطا در اجرای تانل ایران ❌${NC}"

    fi

    sleep 3
}

# ==========================================
# KHAREJ SERVER SETUP
# ==========================================

setup_kharej_tunnel() {

    clear

    echo -e "${CYAN}تنظیم سرور خارج${NC}"

    read -p "شروع رنج پورت: " RANGE_START

    read -p "پایان رنج پورت: " RANGE_END

    read -p "پورت مقصد (مثلا پورت Xray): " TARGET_PORT

    SERVICE_NAME="gost-kharej-range.service"

    CMD="/usr/local/bin/gost"

    for (( p=$RANGE_START; p<=$RANGE_END; p++ ))
    do

        CMD="${CMD} -L relay+mws://0.0.0.0:${p}/127.0.0.1:${TARGET_PORT}"

        ufw allow ${p}/tcp >/dev/null 2>&1

    done

cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Kharej Aggregation Listener
After=network.target

[Service]
Type=simple

ExecStart=${CMD}

Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    systemctl enable ${SERVICE_NAME}

    systemctl restart ${SERVICE_NAME}

    sleep 1

    if systemctl is-active --quiet ${SERVICE_NAME}; then

        echo -e "${GREEN}تانل خارج با موفقیت فعال شد ✔${NC}"

    else

        echo -e "${RED}خطا در اجرای تانل خارج ❌${NC}"

    fi

    sleep 3
}

# ==========================================
# MANAGE
# ==========================================

manage_tunnels() {

clear

files=(/etc/systemd/system/gost-*.service)

if [ ! -e "${files[0]}" ]; then

    echo "هیچ تانلی یافت نشد"
    sleep 2
    return

fi

i=1

for f in "${files[@]}"
do

    name=$(basename "$f")

    status=$(systemctl is-active "$name")

    echo "$i) $name - $status"

    ((i++))

done

read -p "شماره برای حذف (0 خروج): " num

if [ "$num" -gt 0 ]; then

    target=$(basename "${files[$((num-1))]}")

    systemctl stop "$target"

    systemctl disable "$target"

    rm "/etc/systemd/system/$target"

    systemctl daemon-reload

    echo "حذف شد ✔"

fi

sleep 2
}

# ==========================================
# UNINSTALL
# ==========================================

uninstall_all() {

read -p "حذف کامل؟ (y/n): " confirm

if [[ "$confirm" == "y" ]]; then

    systemctl stop gost-* 2>/dev/null

    rm -f /etc/systemd/system/gost-*.service

    rm -f /usr/local/bin/gost

    systemctl daemon-reload

    echo "پاکسازی کامل شد ✔"

    exit

fi

}

# ==========================================
# MENU
# ==========================================

menu() {

while true
do

clear

echo -e "${YELLOW}"
echo "================================"
echo " Gost Aggregation Tunnel FINAL"
echo "================================"
echo -e "${NC}"

echo "1) نصب Gost"
echo "2) تنظیم سرور ایران"
echo "3) تنظیم سرور خارج"
echo "4) مدیریت تانل"
echo "5) حذف کامل"
echo "0) خروج"

read -p "انتخاب: " choice

case $choice in

1) install_prerequisites ;;
2) setup_iran_tunnel ;;
3) setup_kharej_tunnel ;;
4) manage_tunnels ;;
5) uninstall_all ;;
0) exit ;;

esac

done

}

menu
