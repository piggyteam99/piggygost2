#!/usr/bin/env bash
set -euo pipefail

CFG="/etc/gost/tunnels.conf"
MARK="# PIGGYTUN"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

install_gost() {
  # نصب پیش‌نیازها
  if command -v apt >/dev/null; then
    apt update -y && apt install -y wget gzip
  elif command -v yum >/dev/null; then
    yum install -y wget gzip
  elif command -v dnf >/dev/null; then
    dnf install -y wget gzip
  fi

  # دانلود و نصب gost (دقیقاً کدی که شما دادید)
  if [ ! -f "/usr/local/bin/gost" ]; then
      echo "Downloading GOST v2.11.5..."
      wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz -O gost.gz
      
      # استخراج فایل
      gzip -d gost.gz
      
      # انتقال به مسیر اجرایی
      mv gost /usr/local/bin/gost
      
      # دادن دسترسی اجرا
      chmod +x /usr/local/bin/gost
      
      echo "gost با موفقیت نصب شد."
  else
      echo "gost از قبل نصب شده است."
  fi

  # ساخت پوشه کانفیگ و اسکریپت راه‌انداز سرویس
  if [ ! -f "/etc/systemd/system/gost.service" ]; then
    mkdir -p /etc/gost
    
    cat > /etc/gost/run.sh <<'EOF'
#!/bin/bash
CONF="/etc/gost/tunnels.conf"
if [ ! -s "$CONF" ] || ! grep -q "\-L" "$CONF"; then
    echo "No tunnels configured. Waiting..."
    sleep infinity
    exit 0
fi
ARGS=()
while IFS= read -r line || [ -n "$line" ]; do
    # حذف خطوط خالی و کامنت‌ها برای پاس دادن به GOST
    if [[ -n "$line" ]] && [[ "$line" != "#"* ]]; then
        ARGS+=("$line")
    fi
done < "$CONF"
exec /usr/local/bin/gost "${ARGS[@]}"
EOF
    chmod +x /etc/gost/run.sh

    # ساخت سرویس
    cat > /etc/systemd/system/gost.service <<EOF
[Unit]
Description=GOST Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=/etc/gost/run.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable gost >/dev/null 2>&1 || true
    echo "Service configured."
  fi
}

init_cfg_if_needed() {
  if [[ ! -f "$CFG" ]]; then
    echo "Creating base config..."
    mkdir -p /etc/gost
    touch "$CFG"
  fi
}

ask() {
  read -rp "$1: " v
  echo "$v"
}

restart_gost() {
  systemctl restart gost
}

add_tunnel_iran() {

main_port=$(ask "Main listen port")
range_start=$(ask "Port range start")
count=$(ask "Port count")
kharej_ip=$(ask "Kharej IP")

id="IRAN_${main_port}_${range_start}_${count}"

# ایجاد لیست تارگت‌ها برای پخش بار (Load Balancing) در گوست
targets=""
for ((i=0;i<count;i++)); do
    p=$((range_start+i))
    targets="${targets}127.0.0.1:${p},"
done
targets=${targets%,} # حذف کاما از انتهای رشته

cat >> "$CFG" <<EOF
$MARK START $id
-L tcp://:$main_port/$targets?strategy=round
EOF

for ((i=0;i<count;i++)); do
p=$((range_start+i))
echo "-L tcp://:$p/$kharej_ip:$p" >> "$CFG"
done

echo "$MARK END $id" >> "$CFG"

restart_gost

echo "Tunnel added: $id"
}

add_tunnel_kharej() {

range_start=$(ask "Port range start")
count=$(ask "Port count")
dest_port=$(ask "Destination local port")

id="KHAREJ_${range_start}_${count}_${dest_port}"

cat >> "$CFG" <<EOF
$MARK START $id
EOF

for ((i=0;i<count;i++)); do
p=$((range_start+i))
echo "-L tcp://:$p/127.0.0.1:$dest_port" >> "$CFG"
done

echo "$MARK END $id" >> "$CFG"

restart_gost

echo "Tunnel added: $id"
}

list_tunnels() {
  if [[ -f "$CFG" ]]; then
    grep "$MARK START" "$CFG" | nl
  else
    echo "No config file found."
  fi
}

remove_tunnel() {

list_tunnels

num=$(ask "Enter number to remove")

id=$(grep "$MARK START" "$CFG" | sed -n "${num}p" | awk '{print $4}')

if [[ -z "$id" ]]; then
  echo "Invalid"
  exit 1
fi

sed -i "/$MARK START $id/,/$MARK END $id/d" "$CFG"

restart_gost

echo "Removed: $id"
}

remove_all() {

systemctl stop gost || true
systemctl disable gost || true

rm -f "$CFG"
rm -f /etc/gost/run.sh

read -rp "Remove GOST completely? (y/n): " r

if [[ "$r" == "y" ]]; then
  rm -rf /etc/gost
  rm -f /usr/local/bin/gost
  rm -f /etc/systemd/system/gost.service
  systemctl daemon-reload
fi

echo "All removed"

exit 0
}

iran_menu() {

while true; do

echo
echo "IRAN MENU"
echo "1) Install GOST"
echo "2) Add Tunnel"
echo "3) List Tunnels"
echo "4) Remove Tunnel"
echo "5) Back"

c=$(ask "Choice")

case $c in

1)
install_gost
init_cfg_if_needed
;;

2)
install_gost
init_cfg_if_needed
add_tunnel_iran
;;

3)
list_tunnels
;;

4)
remove_tunnel
;;

5)
break
;;

esac

done

}

kharej_menu() {

while true; do

echo
echo "KHAREJ MENU"
echo "1) Install GOST"
echo "2) Add Tunnel"
echo "3) List Tunnels"
echo "4) Remove Tunnel"
echo "5) Back"

c=$(ask "Choice")

case $c in

1)
install_gost
init_cfg_if_needed
;;

2)
install_gost
init_cfg_if_needed
add_tunnel_kharej
;;

3)
list_tunnels
;;

4)
remove_tunnel
;;

5)
break
;;

esac

done

}

echo
echo "MAIN MENU"
echo "1) IRAN SERVER"
echo "2) KHAREJ SERVER"
echo "3) REMOVE ALL"

main=$(ask "Select")

case $main in

1)
iran_menu
;;

2)
kharej_menu
;;

3)
remove_all
;;

*)
echo "Invalid"
;;

esac

echo "Done"
