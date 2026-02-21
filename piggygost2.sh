#!/bin/bash

# ==========================================
# Gost Bandwidth Aggregation (Relay+MWS) - Fixed
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
    echo -e "${CYAN}در حال نصب و بروزرسانی پیش‌نیازها...${NC}"
    apt-get update -y
    apt-get install -y wget curl tar ufw

    if [ ! -f "/usr/local/bin/gost" ]; then
        echo -e "${YELLOW}در حال دانلود Gost...${NC}"
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
    echo -e "${YELLOW}--- تنظیمات سرور ایران ---${NC}"
    read -p "پورت داخلی (ایران): " LOCAL_PORT
    read -p "آی‌پی سرور خارج: " FOREIGN_IP
    read -p "پورت کانفیگ V2ray در سرور خارج: " TARGET_PORT
    read -p "شروع رنج پورت لودبالانس: " RANGE_START
    read -p "پایان رنج پورت لودبالانس: " RANGE_END
    
    echo -e "${CYAN}در حال پیکربندی...${NC}"
    
    # ساخت لیست نودها با کاما
    HOSTS=""
    for (( p=$RANGE_START; p<=$RANGE_END; p++ )); do
        if [ -z "$HOSTS" ]; then
            HOSTS="${FOREIGN_IP}:${p}"
        else
            HOSTS="${HOSTS},${FOREIGN_IP}:${p}"
        fi
    done
    
    # اصلاح مهم: حذف max_fails برای جلوگیری از ارور none node available
    # اضافه کردن keepalive برای پایداری بیشتر
    F_STR="relay+mws://${HOSTS}?strategy=round&keepalive=true"

    SERVICE_NAME="gost-ir-${LOCAL_PORT}.service"
    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Iran Tunnel (LoadBalanced)
After=network.target

[Service]
Type=simple
# دستور اجرا: دریافت از پورت لوکال و پخش بین پورت‌های خارج
ExecStart=/usr/local/bin/gost -L tcp://0.0.0.0:${LOCAL_PORT}/127.0.0.1:${TARGET_PORT} -F "${F_STR}"
Restart=always
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME >/dev/null 2>&1
    systemctl start $SERVICE_NAME
    ufw allow $LOCAL_PORT/tcp >/dev/null 2>&1

    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}✅ تانل ایران با موفقیت فیکس و فعال شد!${NC}"
        echo -e "${YELLOW}وضعیت:${NC}"
        systemctl status $SERVICE_NAME --no-pager | grep "Active:"
    else
        echo -e "${RED}❌ خطا در استارت سرویس!${NC}"
        journalctl -u $SERVICE_NAME --no-pager -n 5
    fi
    echo ""
    read -p "اینتر بزنید تا به منو برگردید..."
}

setup_kharej_tunnel() {
    clear
    echo -e "${YELLOW}--- تنظیمات سرور خارج ---${NC}"
    read -p "شروع رنج پورت: " RANGE_START
    read -p "پایان رنج پورت: " RANGE_END
    
    echo -e "${CYAN}در حال باز کردن پورت‌ها...${NC}"

    L_STR=""
    for (( p=$RANGE_START; p<=$RANGE_END; p++ )); do
        # لیسن کردن روی تمام پورت‌ها با پروتکل relay+mws
        L_STR="${L_STR} -L relay+mws://0.0.0.0:${p}"
        ufw allow $p/tcp >/dev/null 2>&1
    done

    SERVICE_NAME="gost-kh-range.service"
    cat <<EOF > /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Gost Kharej Multi-Port Listener
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost ${L_STR}
Restart=always
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME >/dev/null 2>&1
    systemctl start $SERVICE_NAME

    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}✅ سرور خارج آماده دریافت ترافیک است!${NC}"
        systemctl status $SERVICE_NAME --no-pager | grep "Active:"
    else
        echo -e "${RED}❌ خطا در سرور خارج!${NC}"
    fi
    echo ""
    read -p "اینتر بزنید تا به منو برگردید..."
}

manage_tunnels() {
    clear
    files=(/etc/systemd/system/gost-*.service)
    if [ ! -e "${files[0]}" ]; then
        echo -e "${RED}هیچ تانلی یافت نشد!${NC}"
        sleep 2
        return
    fi
    
    echo -e "${CYAN}لیست تانل‌های فعال:${NC}"
    count=1
    for f in "${files[@]}"; do
        filename=$(basename -- "$f")
        status=$(systemctl is-active "$filename")
        if [[ "$status" == "active" ]]; then
            color=$GREEN
        else
            color=$RED
        fi
        echo -e "${count}) ${filename} -> [${color}${status}${NC}]"
        ((count++))
    done
    
    echo "---------------------------------"
    echo "1) حذف سرویس | 0) بازگشت"
    read -p "انتخاب: " choice
    if [ "$choice" == "1" ]; then
        read -p "شماره سرویس برای حذف: " del_num
        idx=$((del_num-1))
        target=$(basename -- "${files[$idx]}")
        systemctl stop "$target"
        systemctl disable "$target" >/dev/null 2>&1
        rm "${files[$idx]}"
        systemctl daemon-reload
        echo -e "${GREEN}سرویس حذف شد.${NC}"
        sleep 1
    fi
}

uninstall_all() {
    read -p "پاکسازی کامل و حذف همه تانل‌ها؟ (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for f in /etc/systemd/system/gost-*.service; do
            if [ -e "$f" ]; then
                name=$(basename -- "$f")
                systemctl stop "$name"
                systemctl disable "$name"
                rm "$f"
            fi
        done
        systemctl daemon-reload
        rm -f /usr/local/bin/gost
        echo -e "${GREEN}همه چیز پاک شد.${NC}"
        sleep 2
    fi
}

menu() {
    while true; do
        clear
        echo -e "${YELLOW}=== Gost LoadBalancing Fix ===${NC}"
        echo "1) نصب هسته Gost"
        echo "2) کانفیگ سرور ایران (Fix: None Node Available)"
        echo "3) کانفیگ سرور خارج"
        echo "4) مدیریت و حذف تانل‌ها"
        echo "5) پاکسازی کامل"
        echo "0) خروج"
        echo "----------------------------"
        read -p "گزینه: " choice
        case $choice in
            1) install_prerequisites ;;
            2) setup_iran_tunnel ;;
            3) setup_kharej_tunnel ;;
            4) manage_tunnels ;;
            5) uninstall_all ;;
            0) exit 0 ;;
            *) echo "نامعتبر" ; sleep 1 ;;
        esac
    done
}
menu
