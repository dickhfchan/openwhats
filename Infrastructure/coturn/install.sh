#!/usr/bin/env bash
# Install and configure coturn on the OpenWhats EC2 instance.
# Run as: ssh ubuntu@3.222.228.217 'bash -s' < install.sh
set -euo pipefail

TURN_SECRET="${TURN_SECRET:-change-me-in-production}"

echo "=== Installing coturn ==="
apt-get update -q
apt-get install -y coturn

echo "=== Writing config ==="
mkdir -p /var/log/coturn
cp turnserver.conf /etc/coturn/turnserver.conf
# Inject the secret from env
sed -i "s/CHANGE_ME_MATCHES_TURN_SECRET_IN_ENV/${TURN_SECRET}/" /etc/coturn/turnserver.conf

# Enable coturn service
sed -i 's/#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn

echo "=== Opening firewall ports ==="
# UDP/TCP 3478 (TURN/STUN)
# TCP 5349 (TURNS)
# UDP 49152-65535 (relay range)
ufw allow 3478/udp comment "STUN/TURN"
ufw allow 3478/tcp comment "STUN/TURN TCP"
ufw allow 5349/tcp comment "TURNS TLS"
ufw allow 49152:65535/udp comment "WebRTC relay range"

echo "=== Starting coturn ==="
systemctl enable coturn
systemctl restart coturn
systemctl status coturn --no-pager

echo "=== Verifying TURN (requires turnutils_uclient) ==="
command -v turnutils_uclient && \
    turnutils_uclient -T -u test -w test 3.222.228.217 || true

echo "Done. TURN server running on 3478/5349."
