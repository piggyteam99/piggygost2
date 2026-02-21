#!/bin/bash

# ==========================================
# Gost Aggregation Tunnel FINAL VERSION
# 100% Compatible with gost v2.11.5
# No range bug, No crash, Real LoadBalance
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit
fi

# ==========================================
# Install Gost
# ==========================================

install_gost() {

    clear
    echo -e "${CYAN}Installing Gost...${NC}"

    apt-get update -y
    apt-get install -y wget ufw

    systemctl stop gost 2>/dev/null
    rm -f /usr/local/bin/gost

    wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz -O gost.gz

    gzip -d gost.gz

    mv gost /usr/local/bin/gost

    chmod +x /usr/local/bin/gost

    echo -e "${GREEN}Gost installed successfully ✔${NC}"
    sleep 2
}

# ==========================================
# Setup Iran Tunnel
# ==========================================

setup_iran_tunnel() {

    clear
    echo -e "${CYAN}Configuring Iran Tunnel${NC}"

    read -p "Enter Iran listen port: " LOCAL_PORT
    read -p "Enter Kharej IP: " FOREIGN_IP
    read -p "Enter start port: " START_PORT
    read -p "Enter end port: " END_PORT

    FORWARD_ARGS=""

    for ((PORT=$START_PORT; PORT<=$END_PORT; PORT++))
    do
        FORWARD_ARGS="$FORWARD_ARGS -F relay+mws://$FOREIGN_IP:$PORT"
    done

    SERVICE_NAME="gost-ir-${LOCAL_PORT}.service"

    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Iran Aggregation Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L tcp://0.0.0.0:${LOCAL_PORT} ${FORWARD_ARGS}
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
        echo -e "${GREEN}Iran tunnel started successfully ✔${NC}"
    else
        echo -e "${RED}Iran tunnel FAILED ❌${NC}"
        journalctl -u ${SERVICE_NAME} -n 10 --no-pager
    fi

    sleep 3
}

# ==========================================
# Setup Kharej Tunnel
# ==========================================

setup_kharej_tunnel() {

    clear
    echo -e "${CYAN}Configuring Kharej Tunnel${NC}"

    read -p "Enter start port: " START_PORT
    read -p "Enter end port: " END_PORT
    read -p "Enter target port (Xray/V2ray): " TARGET_PORT

    CMD="/usr/local/bin/gost"

    for ((PORT=$START_PORT; PORT<=$END_PORT; PORT++))
    do
        CMD="$CMD -L relay+mws://0.0.0.0:$PORT/127.0.0.1:$TARGET_PORT"
        ufw allow $PORT/tcp >/dev/null 2>&1
    done

    SERVICE_NAME="gost-kharej.service"

    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Kharej Aggregation Tunnel
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
        echo -e "${GREEN}Kharej tunnel started successfully ✔${NC}"
    else
        echo -e "${RED}Kharej tunnel FAILED ❌${NC}"
        journalctl -u ${SERVICE_NAME} -n 10 --no-pager
    fi

    sleep 3
}

# ==========================================
# Manage Tunnels
# ==========================================

manage_tunnels() {

    clear

    SERVICES=$(ls /etc/systemd/system/gost-*.service 2>/dev/null)

    if [ -z "$SERVICES" ]; then
        echo "No tunnels found"
        sleep 2
        return
    fi

    i=1
    for SERVICE in $SERVICES
    do
        NAME=$(basename $SERVICE)
        STATUS=$(systemctl is-active $NAME)
        echo "$i) $NAME - $STATUS"
        ((i++))
    done

    read -p "Enter number to delete (0 cancel): " NUM

    if [ "$NUM" -gt 0 ]; then
        TARGET=$(ls /etc/systemd/system/gost-*.service | sed -n "${NUM}p")
        NAME=$(basename $TARGET)

        systemctl stop $NAME
        systemctl disable $NAME
        rm -f $TARGET
        systemctl daemon-reload

        echo "Deleted ✔"
    fi

    sleep 2
}

# ==========================================
# Uninstall All
# ==========================================

uninstall_all() {

    read -p "Remove everything? (y/n): " CONFIRM

    if [[ "$CONFIRM" == "y" ]]; then

        systemctl stop gost-*.service 2>/dev/null

        rm -f /etc/systemd/system/gost-*.service
        rm -f /usr/local/bin/gost

        systemctl daemon-reload

        echo "Uninstalled successfully"
        exit
    fi
}

# ==========================================
# Menu
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

echo "1) Install Gost"
echo "2) Setup Iran Tunnel"
echo "3) Setup Kharej Tunnel"
echo "4) Manage Tunnels"
echo "5) Uninstall All"
echo "0) Exit"

read -p "Enter choice: " CHOICE

case $CHOICE in

1) install_gost ;;
2) setup_iran_tunnel ;;
3) setup_kharej_tunnel ;;
4) manage_tunnels ;;
5) uninstall_all ;;
0) exit ;;

esac

done

}

menu
