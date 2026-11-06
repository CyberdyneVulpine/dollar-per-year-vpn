{
set -e

echo "=== 1. Port Detection ==="
SSH_NAT_PORT=$(grep -iE "^Port\s+[0-9]+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1 || true)
[ -z "$SSH_NAT_PORT" ] && SSH_NAT_PORT=$(ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | head -n1 || true)

DEFAULT_PORT="3507"
[ -n "$SSH_NAT_PORT" ] && [ "$SSH_NAT_PORT" != "22" ] && DEFAULT_PORT="$SSH_NAT_PORT"

if [ -c /dev/tty ]; then
    printf "Enter WireGuard UDP Listen Port [Default %s]: " "$DEFAULT_PORT"
    read -r INPUT_PORT < /dev/tty 2>/dev/null || INPUT_PORT=""
    WG_PORT="${INPUT_PORT:-$DEFAULT_PORT}"
else
    WG_PORT="$DEFAULT_PORT"
fi
echo "[+] Using WireGuard Listen Port: ${WG_PORT}"

echo "=== 2. Creating 256MB Swap File ==="
if [ ! -f /swapfile ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=256 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
    echo "[+] 256MB Swap active."
fi

echo "=== 3. SSH Configuration ==="
SSH_CONF="/etc/ssh/sshd_config"
if [ -f "$SSH_CONF" ]; then
    sed -i 's/^#\?AllowTcpForwarding.*/AllowTcpForwarding yes/' "$SSH_CONF"
    sed -i 's/^#\?GatewayPorts.*/GatewayPorts no/' "$SSH_CONF"
    sed -i 's/^#\?PermitTunnel.*/PermitTunnel yes/' "$SSH_CONF"

    grep -q "^AllowTcpForwarding" "$SSH_CONF" || echo "AllowTcpForwarding yes" >> "$SSH_CONF"
    grep -q "^GatewayPorts" "$SSH_CONF" || echo "GatewayPorts no" >> "$SSH_CONF"
    grep -q "^PermitTunnel" "$SSH_CONF" || echo "PermitTunnel yes" >> "$SSH_CONF"

    rc-service sshd reload || rc-service sshd restart
fi

echo "=== 4. Safe Cleanup of 'alpine' User ==="
if id alpine >/dev/null 2>&1; then
    if ps -u alpine >/dev/null 2>&1; then
        echo "[!] User 'alpine' has active processes running. Skipping deletion."
    else
        deluser --remove-home alpine || true
        echo "[+] User 'alpine' removed."
    fi
fi

echo "=== 5. Cleaning Old WireGuard Configurations ==="
rc-service wg-quick.wg0 stop 2>/dev/null || true
ip link delete dev wg0 2>/dev/null || true
rm -rf /etc/wireguard/*
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

echo "=== 6. Packages & Kernel Modules ==="
apk update
apk add --no-cache wireguard-tools iptables libqrencode-tools curl
modprobe ip_tables iptable_nat iptable_filter 2>/dev/null || true

echo "=== 7. Enabling IP Forwarding ==="
cat << 'EOF' > /etc/sysctl.d/99-wireguard.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-wireguard.conf >/dev/null

echo "=== 8. Generating Server Keys ==="
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
chmod 600 /etc/wireguard/server_private.key
SERVER_PRIV=$(cat /etc/wireguard/server_private.key)

echo "=== 9. Building Server Config ==="
EXT_IF=$(ip route show default | awk '/default/ {print $5}' | head -n 1)
[ -z "$EXT_IF" ] && EXT_IF="eth0"

cat << EOF > /etc/wireguard/wg0.conf
[Interface]
Address = 10.8.0.1/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}

PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${EXT_IF} -j MASQUERADE; iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
PostDown = iptables -D FORWARD -i %i -j ACCEPT 2>/dev/null || true; iptables -D FORWARD -o %i -j ACCEPT 2>/dev/null || true; iptables -t nat -D POSTROUTING -o ${EXT_IF} -j MASQUERADE 2>/dev/null || true; iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
EOF
chmod 600 /etc/wireguard/wg0.conf

echo "=== 10. Creating Global Command: wg-add ==="
cat << 'EOF' > /usr/local/bin/wg-add
#!/bin/sh
CLIENT_NAME="$1"
if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: wg-add <client_name>"
    exit 1
fi

WG_DIR="/etc/wireguard"
SERVER_PUB_KEY=$(cat "${WG_DIR}/server_public.key")
SERVER_IP=$(curl -s4 ifconfig.me || wget -qO- eth0.me)
SERVER_PORT=$(grep -i "^ListenPort" "${WG_DIR}/wg0.conf" | awk '{print $3}')

OCTET=2
while grep -q "10.8.0.${OCTET}/32" "${WG_DIR}/wg0.conf"; do
    OCTET=$((OCTET + 1))
    if [ "$OCTET" -gt 254 ]; then
        echo "Error: IP pool exhausted."
        exit 1
    fi
done
CLIENT_IP="10.8.0.${OCTET}"

CLIENT_PRIV_KEY=$(wg genkey)
CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
CLIENT_PSK=$(wg genpsk)

cat << CONFIG >> "${WG_DIR}/wg0.conf"

# Client: ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
AllowedIPs = ${CLIENT_IP}/32
CONFIG

rc-service wg-quick.wg0 restart >/dev/null 2>&1

CLIENT_CONF=$(cat << CONF
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP}/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PSK}
Endpoint = ${SERVER_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
CONF
)

echo "$CLIENT_CONF" > "/root/${CLIENT_NAME}.conf"

echo "====================================================="
echo "Client '${CLIENT_NAME}' created!"
echo "Saved to server at: /root/${CLIENT_NAME}.conf"
echo "====================================================="
echo "$CLIENT_CONF"
echo "====================================================="
echo "$CLIENT_CONF" | qrencode -t ansiutf8
EOF
chmod +x /usr/local/bin/wg-add

echo "=== 11. Creating Global Command: wg-remove ==="
cat << 'EOF' > /usr/local/bin/wg-remove
#!/bin/sh
CLIENT_NAME="$1"
if [ -z "$CLIENT_NAME" ]; then
    echo "Usage: wg-remove <client_name>"
    exit 1
fi

CONF="/etc/wireguard/wg0.conf"
if ! grep -q "^# Client: ${CLIENT_NAME}$" "$CONF"; then
    echo "Error: Client '${CLIENT_NAME}' not found in $CONF."
    exit 1
fi

sed -i "/^# Client: ${CLIENT_NAME}$/,/^AllowedIPs = .*/d" "$CONF"

rc-service wg-quick.wg0 restart >/dev/null 2>&1
rm -f "/root/${CLIENT_NAME}.conf"

echo "[+] Client '${CLIENT_NAME}' has been permanently removed."
EOF
chmod +x /usr/local/bin/wg-remove

echo "=== 12. Creating Global Command: wg-list ==="
cat << 'EOF' > /usr/local/bin/wg-list
#!/bin/sh
echo "==============================================================="
printf "%-15s | %-15s | %s\n" "IP Address" "Client Name" "Public Key (Truncated)"
echo "==============================================================="
grep -E '^# Client:|^AllowedIPs =|^PublicKey =' /etc/wireguard/wg0.conf | while read -r line; do
    if echo "$line" | grep -q '^# Client:'; then
        NAME=$(echo "$line" | awk '{print $3}')
    elif echo "$line" | grep -q '^PublicKey ='; then
        PUBKEY=$(echo "$line" | awk '{print $3}')
    elif echo "$line" | grep -q '^AllowedIPs ='; then
        IP=$(echo "$line" | awk '{print $3}' | cut -d/ -f1)
        printf "%-15s | %-15s | %s\n" "$IP" "$NAME" "${PUBKEY:0:20}..."
    fi
done
echo "==============================================================="
EOF
chmod +x /usr/local/bin/wg-list

echo "=== 13. Starting WireGuard ==="
[ ! -e /etc/init.d/wg-quick.wg0 ] && ln -s /etc/init.d/wg-quick /etc/init.d/wg-quick.wg0
rc-update add wg-quick.wg0 default
rc-service wg-quick.wg0 zap 2>/dev/null || true
ip link delete dev wg0 2>/dev/null || true
rc-service wg-quick.wg0 start

echo "====================================================="
echo "[+] Deployment complete! Listening on Port ${WG_PORT}"
echo ""
echo "Commands installed globally:"
echo "  wg-add <name>   -> Generate a new client, QR code, and .conf file"
echo "  wg-remove <name>-> Instantly revoke a client and delete their config"
echo "  wg-list         -> View all active issued tokens"
echo "====================================================="
}