#!/bin/sh
set -e

echo "=== Running one-time update (temporary swap) ==="
fallocate -l 128M /swapfiletemp
chmod 600 /swapfiletemp
mkswap /swapfiletemp >/dev/null
swapon /swapfiletemp
apk update
apk upgrade
swapoff /swapfiletemp
rm /swapfiletemp
echo "[+] System updated."

echo "=== Installing daily autoupdate script ==="
cat << 'EOF' > /etc/periodic/daily/alpine-autoupdate
#!/bin/sh
# Create temporary swap for low RAM
fallocate -l 128M /swapfiletemp
chmod 600 /swapfiletemp
mkswap /swapfiletemp
swapon /swapfiletemp

# Run the update quietly
apk update -q
apk upgrade -q

# Remove temporary swap
swapoff /swapfiletemp
rm /swapfiletemp
EOF
chmod +x /etc/periodic/daily/alpine-autoupdate
echo "[+] /etc/periodic/daily/alpine-autoupdate installed."

echo "=== Enabling crond ==="
rc-update add crond default 2>/dev/null || true
rc-service crond start 2>/dev/null || rc-service crond restart 2>/dev/null || true
echo "[+] Daily autoupdate is configured."
