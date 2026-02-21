#!/bin/bash

# ==========================================
# Gost Bandwidth Aggregation (Relay+MWS)
# FIXED VERSION WITH REAL LOAD BALANCE
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

install_prerequisites() {

    clear
    echo -e "${CYAN}در حال نصب پیش‌نیازها...${NC}"

    apt-get update
    apt-get install -y wget curl tar ufw

    if [ ! -f "/usr/local/bin/gost" ]; then

        wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz -O gost.gz
        gzip -d gost.gz
        mv gost /usr/local/bin/gost
        chmod +x /usr/local/bin/gost

    fi

    echo -e "${GREEN}نصب با موفقیت انجام شد.${NC}"
    sleep 2
}

setup_iran_tunnel() {

    clear

    read -p "پورت داخلی (ایران): " LOCAL_PORT
    read -p "آی‌پی سرور خارج: " FOREIGN_IP
    read -p "پورت مقصد واقعی (مثلا پورت xray): " TARGET_PORT
    read -p "شروع رنج پورت: " RANGE_START
    read -p "پایان رنج پورت: " RANGE_END

    echo -e "${CYAN}ساخت لیست LoadBalance...${NC}"

    PORT_LIST=""

    for (( p=$RANGE_START; p<=$RANGE_END; p++ ))
    do

        if [ -z "$PORT_LIST" ]; then
            PORT_LIST="${FOREIGN_IP}:${p}"
        else
            PORT_LIST="${PORT_LIST},${FOREIGN_IP}:${p}"
        fi

    done

    F_STR="relay+mws://${PORT_LIST}?strategy=round"

    SERVICE_NAME="gost-ir-${LOCAL_PORT}.service"

    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Iran LoadBalance Tunnel
After=network.target

[Service]
Type=simple

ExecStart=/usr/local/bin/gost \
-L tcp://0.0.0.0:${LOCAL_PORT}/127.0.0.1:${TARGET_PORT} \
-F "${F_STR}"

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

        echo -e "${GREEN}تانل ایران فعال شد با LoadBalance واقعی ✔${NC}"

    else

        echo -e "${RED}خطا در اجرای سرویس${NC}"

    fi

    sleep 3
}

setup_kharej_tunnel() {

    clear

    read -p "شروع رنج پورت: " RANGE_START
    read -p "پایان رنج پورت: " RANGE_END
    read -p "پورت مقصد واقعی (مثلا xray): " TARGET_PORT

    SERVICE_NAME="gost-kharej-range.service"

    CMD="/usr/local/bin/gost"

    for (( p=$RANGE_START; p<=$RANGE_END; p++ ))
    do

        CMD="${CMD} -L relay+mws://0.0.0.0:${p}/127.0.0.1:${TARGET_PORT}"

        ufw allow ${p}/tcp >/dev/null 2>&1

    done

cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Kharej MultiPort Listener
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

        echo -e "${GREEN}تانل خارج فعال شد ✔${NC}"

    else

        echo -e "${RED}خطا در اجرای سرویس${NC}"

    fi

    sleep 3
}

manage_tunnels() {

    clear

    files=(/etc/systemd/system/gost-*.service)

    if [ ! -e "${files[0]}" ]; then

        echo "هیچ تانلی وجود ندارد"
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

        echo "حذف شد"

    fi

    sleep 2
}

menu() {

while true
do

clear

echo "================================="
echo "Gost LoadBalance Tunnel FIXED"
echo "================================="

echo "1) نصب"
echo "2) ساخت تانل ایران"
echo "3) ساخت تانل خارج"
echo "4) مدیریت"
echo "0) خروج"

read -p "انتخاب: " c

case $c in

1) install_prerequisites ;;
2) setup_iran_tunnel ;;
3) setup_kharej_tunnel ;;
4) manage_tunnels ;;
0) exit ;;

esac

done

}

menu
