#!/bin/bash
# Polku: BRouter behind Caddy (HTTPS). Log: /var/log/polku-setup.log
exec > /var/log/polku-setup.log 2>&1
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
VER=1.7.10
TILES="E20_N60 E25_N60 E30_N60 E20_N65 E25_N65 E30_N65 E20_N70 E25_N70"

apt-get update
apt-get install -y openjdk-17-jre-headless unzip curl
apt-get install -y caddy || {
  apt-get install -y gnupg debian-keyring debian-archive-keyring apt-transport-https
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update && apt-get install -y caddy
}

# Oracle's Ubuntu image rejects everything but SSH: open 80 and 443 before its REJECT rule
for p in 443 80; do
  n=$(iptables -L INPUT --line-numbers | awk '/REJECT/{print $1; exit}')
  if [ -n "$n" ]; then iptables -I INPUT "$n" -m state --state NEW -p tcp --dport $p -j ACCEPT
  else iptables -A INPUT -m state --state NEW -p tcp --dport $p -j ACCEPT; fi
done
netfilter-persistent save || true

# BRouter
id brouter || useradd --system --home-dir /opt/brouter --shell /usr/sbin/nologin brouter
mkdir -p /opt/brouter/segments4 /opt/brouter/customprofiles
cd /opt/brouter
curl -fsSL -o b.zip "https://github.com/abrensch/brouter/releases/download/v$VER/brouter-$VER.zip"
unzip -q -o b.zip && rm b.zip
ln -sfn "brouter-$VER" current
curl -fsSL -o current/profiles2/fastbike-lowtraffic.brf https://brouter.de/brouter/profiles2/fastbike-lowtraffic.brf \
  || cp current/profiles2/fastbike-verylowtraffic.brf current/profiles2/fastbike-lowtraffic.brf

# Weekly data update: only tiles brouter.de has rebuilt, one at a time, then a restart
cat > /opt/brouter/update.sh <<EOF
#!/bin/bash
cd /opt/brouter
for t in $TILES; do
  f=segments4/\$t.rd5
  curl -fsSL -z "\$f" -o "\$f.part" "https://brouter.de/brouter/segments4/\$t.rd5" && [ -s "\$f.part" ] && mv "\$f.part" "\$f"
  rm -f "\$f.part"
  sleep 5
done
find customprofiles -type f -mtime +7 -delete
chown -R brouter:brouter /opt/brouter
systemctl restart brouter
EOF
chmod +x /opt/brouter/update.sh

cat > /etc/systemd/system/brouter.service <<EOF
[Unit]
Description=BRouter for Polku
After=network-online.target
[Service]
User=brouter
WorkingDirectory=/opt/brouter
ExecStart=/usr/bin/java -Xmx2g -Xms256m -DmaxRunningTime=300 -cp /opt/brouter/current/brouter-$VER-all.jar btools.server.RouteServer segments4 current/profiles2 customprofiles 17777 8 127.0.0.1
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/brouter-update.service <<EOF
[Unit]
Description=Fresh BRouter routing data
[Service]
Type=oneshot
ExecStart=/opt/brouter/update.sh
EOF
cat > /etc/systemd/system/brouter-update.timer <<EOF
[Unit]
Description=Weekly BRouter data update
[Timer]
OnCalendar=Sun 04:00
RandomizedDelaySec=1h
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable brouter brouter-update.timer
/opt/brouter/update.sh
systemctl enable --now brouter-update.timer

# HTTPS with a free hostname from the public IP (e.g. 1-2-3-4.sslip.io)
IP=$(curl -fsS https://api.ipify.org)
HOST="${IP//./-}.sslip.io"
cat > /etc/caddy/Caddyfile <<EOF
$HOST {
  reverse_proxy 127.0.0.1:17777
}
EOF
systemctl enable caddy
systemctl restart caddy
echo "https://$HOST/brouter" > /opt/brouter/URL
echo "DONE https://$HOST/brouter"
