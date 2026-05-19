#!/bin/bash

set -Eeuo pipefail

trap 'echo "[!] ERROR: Installation failed on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root."
    exit 1
fi

echo "[*] UPDATING SYSTEM & INSTALLING DEPENDENCIES"
apt update && apt upgrade -y
apt install -y \
    curl \
    wget \
    jq \
    git \
    lsof \
    ca-certificates \
    gnupg \
    apt-transport-https \
    debian-keyring \
    debian-archive-keyring

echo "[*] INSTALLING MYSQL SERVER"
apt install -y mysql-server

echo "[*] HARDENING MYSQL"

MYSQL_CONFIG="/etc/mysql/mysql.conf.d/mysqld.cnf"

if grep -q "^bind-address" "$MYSQL_CONFIG"; then
    sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' "$MYSQL_CONFIG"
else
    echo "bind-address = 127.0.0.1" >> "$MYSQL_CONFIG"
fi

grep -q "^local_infile" "$MYSQL_CONFIG" \
    && sed -i 's/^local_infile.*/local_infile=0/' "$MYSQL_CONFIG" \
    || echo "local_infile=0" >> "$MYSQL_CONFIG"

grep -q "^symbolic-links" "$MYSQL_CONFIG" \
    && sed -i 's/^symbolic-links.*/symbolic-links=0/' "$MYSQL_CONFIG" \
    || echo "symbolic-links=0" >> "$MYSQL_CONFIG"

grep -q "^skip-symbolic-links" "$MYSQL_CONFIG" \
    || echo "skip-symbolic-links" >> "$MYSQL_CONFIG"

systemctl restart mysql

echo
read -s -p "ENTER FLEET DATABASE PASSWORD: " fleetPass
echo

echo "[*] CREATING FLEET DATABASE & USER"

sudo mysql <<EOF

-- Remove anonymous users
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';

-- Remove remote root
DROP USER IF EXISTS 'root'@'%';

-- Remove test DB
DROP DATABASE IF EXISTS test;

DELETE FROM mysql.db
WHERE Db LIKE 'test%';

-- Create fleet database
CREATE DATABASE IF NOT EXISTS fleet;

-- Create least privilege user
CREATE USER IF NOT EXISTS 'fleet'@'localhost'
IDENTIFIED BY '$fleetPass';

GRANT ALL PRIVILEGES
ON fleet.*
TO 'fleet'@'localhost';

FLUSH PRIVILEGES;
EOF

echo "[*] VERIFYING MYSQL STATUS"

if ! systemctl is-active --quiet mysql; then
    echo "[-] MYSQL IS NOT RUNNING"
    exit 1
fi

echo "[*] INSTALLING REDIS SERVER"
apt install -y redis-server

echo
read -s -p "ENTER REDIS PASSWORD: " redisPass
echo

echo "[*] HARDENING REDIS"

REDIS_CONFIG="/etc/redis/redis.conf"

# Remove old requirepass entries
sed -i '/^requirepass/d' "$REDIS_CONFIG"

# Ensure Redis binds locally
if grep -q "^bind " "$REDIS_CONFIG"; then
    sed -i 's/^bind .*/bind 127.0.0.1 ::1/' "$REDIS_CONFIG"
else
    echo "bind 127.0.0.1 ::1" >> "$REDIS_CONFIG"
fi

# Ensure protected mode
if grep -q "^protected-mode" "$REDIS_CONFIG"; then
    sed -i 's/^protected-mode .*/protected-mode yes/' "$REDIS_CONFIG"
else
    echo "protected-mode yes" >> "$REDIS_CONFIG"
fi

sed -i '/^rename-command FLUSHDB/d' "$REDIS_CONFIG"
sed -i '/^rename-command FLUSHALL/d' "$REDIS_CONFIG"
sed -i '/^rename-command CONFIG/d' "$REDIS_CONFIG"
sed -i '/^rename-command SHUTDOWN/d' "$REDIS_CONFIG"

cat <<EOF >> "$REDIS_CONFIG"

rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command CONFIG ""
rename-command SHUTDOWN ""

EOF

printf "\nrequirepass %s\n" "$redisPass" >> "$REDIS_CONFIG"

systemctl enable redis-server
systemctl restart redis-server

echo "[*] VERIFYING REDIS STATUS"

if ! systemctl is-active --quiet redis-server; then
    echo "[-] REDIS IS NOT RUNNING"
    exit 1
fi

if [ "$(REDISCLI_AUTH="$redisPass" redis-cli ping)" != "PONG" ]; then
    echo "[-] REDIS AUTH FAILED"
    exit 1
fi

echo "[*] DOWNLOADING FLEETDM"

tmpdir=$(mktemp -d)

release_json=$(curl -s https://api.github.com/repos/fleetdm/fleet/releases/latest)

tag=$(echo "$release_json" | jq -r '.tag_name')

fleet_url=$(echo "$release_json" | jq -r '
    .assets[]
    | select(.name | test("linux.tar.gz$"))
    | .browser_download_url
' | head -n1)

fleetctl_url=$(echo "$release_json" | jq -r '
    .assets[]
    | select(.name | test("fleetctl.*linux_amd64.tar.gz$"))
    | .browser_download_url
' | head -n1)

if [ -z "$fleet_url" ] || [ -z "$fleetctl_url" ]; then
    echo "[-] FAILED TO FETCH RELEASE ASSETS"
    exit 1
fi

wget "$fleet_url" \
    -O "$tmpdir/fleet.tar.gz"

echo "[*] EXTRACTING FLEETDM"

mkdir -p "$tmpdir/Fleet"
tar -xf "$tmpdir/fleet.tar.gz" -C "$tmpdir/Fleet"

FLEET_BINARY=$(find "$tmpdir/Fleet" -type f -name fleet | head -n 1)

if [ -z "$FLEET_BINARY" ]; then
    echo "[-] FLEET BINARY NOT FOUND"
    exit 1
fi

mv "$FLEET_BINARY" /usr/local/bin/fleet

chown root:root /usr/local/bin/fleet
chmod 755 /usr/local/bin/fleet


echo "[*] INSTALLING FLEETCTL"

wget "$fleetctl_url" \
    -O "$tmpdir/fleetctl.tar.gz"

mkdir -p "$tmpdir/FleetCTL"
tar -xf "$tmpdir/fleetctl.tar.gz" -C "$tmpdir/FleetCTL"

FLEETCTL_BINARY=$(find "$tmpdir/FleetCTL" -type f -name fleetctl | head -n 1)

if [ -z "$FLEETCTL_BINARY" ]; then
    echo "[-] FLEET BINARY NOT FOUND"
    exit 1
fi

mv "$FLEETCTL_BINARY" /usr/local/bin/fleetctl
chown root:root /usr/local/bin/fleetctl
chmod 755 /usr/local/bin/fleetctl

tmpdir=$(mktemp -d)

echo "[*] CREATING FLEET USER"

if ! id fleet &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false fleet
fi

mkdir -p /etc/fleet
mkdir -p /var/lib/fleet

chown fleet:fleet /var/lib/fleet

echo "[*] CREATING FLEET CONFIG"

cat > /etc/fleet/fleet.yml <<EOF
mysql:
  address: 127.0.0.1:3306
  database: fleet
  username: fleet
  password: $fleetPass

redis:
  address: 127.0.0.1:6379
  password: $redisPass

server:
  address: 127.0.0.1:8080
  tls: false

logging:
  debug: false
  json: true
EOF

chown -R fleet:fleet /etc/fleet
chmod 600 /etc/fleet/fleet.yml

echo "[*] PREPARING FLEET DATABASE"

sudo -u fleet /usr/local/bin/fleet prepare db \
    --config /etc/fleet/fleet.yml

echo "[*] CREATING SYSTEMD SERVICE"

cat > /etc/systemd/system/fleet.service <<EOF
[Unit]
Description=FleetDM
After=network.target mysql.service redis-server.service

[Service]
User=fleet
Group=fleet

ExecStart=/usr/local/bin/fleet serve --config /etc/fleet/fleet.yml

Restart=always
RestartSec=5

LimitNOFILE=65535

NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true

ProtectSystem=full
ProtectHome=true

ProtectKernelTunables=true
ProtectControlGroups=true

RestrictRealtime=true
RestrictSUIDSGID=true

LockPersonality=true
MemoryDenyWriteExecute=true

ReadWritePaths=/var/lib/fleet

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fleet
systemctl restart fleet

echo "[*] VERIFYING FLEET STATUS"

if ! systemctl is-active --quiet fleet; then
    echo "[-] FLEET FAILED TO START"
    journalctl -u fleet --no-pager -n 50
    exit 1
fi

echo "[*] WAITING FOR FLEET TO START"
sleep 10

if ! lsof -i :8080 | grep -qi fleet; then
    echo "[-] FLEET IS NOT LISTENING ON PORT 8080"
    exit 1
fi

echo "[*] INSTALLING CADDY"

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list

apt update
apt install -y caddy

echo
read -p "ENTER DOMAIN NAME: " domain

echo
read -p "ENTER WHITELISTED IPs (SPACE SEPARATED): " -ra whiteListedIPs

ip_list="${whiteListedIPs[*]}"

echo "[*] CONFIGURING CADDY"

cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null || true

cat > /etc/caddy/Caddyfile <<EOF
$domain {

    @blocked {
        not remote_ip $ip_list 127.0.0.1 ::1
    }

    respond @blocked "Forbidden" 403

    reverse_proxy 127.0.0.1:8080
}
EOF

if ! caddy validate --config /etc/caddy/Caddyfile; then
    echo "[-] INVALID CADDY CONFIG"
    exit 1
fi

echo "MAKE SURE YOUR DNS IS POINTING TO THE DOMAIN SPECIFIED FOR THE CADDY!!!"
read -p "[PRESS ENTER]"

systemctl enable caddy
systemctl restart caddy

if ! systemctl is-active --quiet caddy; then
    echo "[-] CADDY FAILED TO START"
    journalctl -u caddy --no-pager -n 50
    exit 1
fi

echo "[*] CONFIGURING FIREWALL"

if command -v ufw &>/dev/null; then
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
fi

echo
echo "[+] INSTALLATION COMPLETE"
echo "[+] FleetDM is running behind Caddy"
echo "[+] MySQL bound to localhost only"
echo "[+] Redis bound to localhost only"
echo "[+] Admin access restricted by IP whitelist"
echo
echo "[:D] ENJOY!"
