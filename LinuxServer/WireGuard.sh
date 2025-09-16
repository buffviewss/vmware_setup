#!/bin/bash
set -e

##########################
#  Configuration Variables
##########################

WG_INTERFACE="wg0"
WG_PORT=51820
WG_SUBNET="10.0.0.0/24"          # VPN subnet for WireGuard (clients)
WG_SERVER_IP="10.0.0.1"          # Server's VPN IP (first IP in WG_SUBNET)
LAN_INTERFACE="eth0"            # Interface name of local LAN (if needed)
WAN_INTERFACE="eth1"            # Interface name connected to Internet
SOCKS5_PROXY="eyvizq4mf8n3:6jo0C8dNSfrtkclt@217.180.44.121:6012"  # SOCKS5 proxy (with user:pass@IP:PORT)

# Derived values
WG_NETMASK="${WG_SUBNET#*/}"
WG_NETWORK="${WG_SUBNET%/*}"
SOCKS_HOST="${SOCKS5_PROXY#*@}"
SOCKS_HOST="${SOCKS_HOST%:*}"
SOCKS_PORT="${SOCKS5_PROXY##*:}"
TUN_INTERFACE="tun1"
TUN_IP="198.18.0.1"              # IP for the tun interface
TUN_VIRT="198.18.0.2"            # Virtual router IP on the TUN (must differ by 1 in subnet)
ORIG_GW="$(ip route show default | awk '/default/ {print $3}')"
ORIG_IF="$(ip route show default | awk '/default/ {print $5}')"

log() {
  echo "[*] $@" 1>&2
}

error_exit() {
  echo "Error: $@" 1>&2
  exit 1
}

#####################
#  Install Packages
#####################

log "Updating apt and installing required packages..."
apt-get update -qq || error_exit "apt-get update failed"
apt-get install -y --no-install-recommends \
    wireguard iptables iproute2 unzip || error_exit "apt-get install failed"

# Optional: iptables-persistent if you want to save rules, not used in this script

###################################
#  Enable IP forwarding (IPv4)
###################################
log "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 || error_exit "Failed to enable IPv4 forwarding"

#####################
#  WireGuard Setup
#####################

log "Generating WireGuard keys..."
SERVER_PRIV_KEY="$(wg genkey)"
SERVER_PUB_KEY="$(echo "$SERVER_PRIV_KEY" | wg pubkey)"

log "Writing WireGuard server config to /etc/wireguard/${WG_INTERFACE}.conf"
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
cat > /etc/wireguard/${WG_INTERFACE}.conf <<EOF
[Interface]
Address = ${WG_SERVER_IP}/${WG_NETMASK}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
# Enable packet forwarding/NAT on interface up/down
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_INTERFACE} -j MASQUERADE
EOF
chmod 600 /etc/wireguard/${WG_INTERFACE}.conf

# Note: Client peer configs (public keys, etc.) should be added separately; the script does not output any private keys or client details.
# Also ensure the WG subnets and allowed-IPs on the clients are set (e.g. AllowedIPs = 0.0.0.0/0 for full-tunnel).

log "Bringing up WireGuard interface ${WG_INTERFACE}..."
wg-quick up ${WG_INTERFACE} || error_exit "Failed to bring up WireGuard interface"

###################################
#  tun2socks (BadVPN) Setup
###################################

log "Creating TUN interface ${TUN_INTERFACE}..."
ip tuntap add dev ${TUN_INTERFACE} mode tun user nobody || error_exit "Failed to add TUN device"
ip addr add ${TUN_IP}/30 dev ${TUN_INTERFACE} || error_exit "Failed to set IP on TUN device"
ip link set dev ${TUN_INTERFACE} up || error_exit "Failed to set TUN up"

# Configure routes: force default route through tun1, except for the SOCKS5 server
log "Configuring routes: routing all traffic via ${TUN_INTERFACE} (SOCKS5 proxy)"
# Remove existing default route
ip route del default dev ${ORIG_IF} || true
# Route only the SOCKS proxy host via original gateway
ip route add ${SOCKS_HOST} via ${ORIG_GW} dev ${ORIG_IF} proto static || error_exit "Failed to route proxy host"
# Route default via the TUN interface’s “virtual” router IP
ip route add default via ${TUN_VIRT} dev ${TUN_INTERFACE} metric 1 || error_exit "Failed to add default route via TUN"
# Also add original default as a backup (higher metric)
ip route add default via ${ORIG_GW} dev ${ORIG_IF} metric 10

# Start tun2socks (BadVPN) in gateway mode
log "Starting tun2socks (Badvpn) on ${TUN_INTERFACE} -> ${SOCKS5_PROXY}..."
badvpn-tun2socks --tundev ${TUN_INTERFACE} \
                 --netif-ipaddr ${TUN_VIRT} --netif-netmask 255.255.255.252 \
                 --socks-server-addr ${SOCKS_HOST}:${SOCKS_PORT} &> /var/log/tun2socks.log &
TUN2SOCKS_PID=$!
sleep 1
if ! kill -0 $TUN2SOCKS_PID 2>/dev/null; then
    error_exit "tun2socks failed to start (check /var/log/tun2socks.log)"
fi

###################################
#  Firewall (iptables) Rules
###################################

log "Setting up firewall rules (iptables)..."
# Flush custom chains (optional: ensure clean slate)
iptables -t nat -F
iptables -t mangle -F
iptables -F

# Allow established connections
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow traffic from WG tunnel to tun1 (so proxying works)
iptables -A FORWARD -i ${WG_INTERFACE} -o ${TUN_INTERFACE} -j ACCEPT
iptables -A FORWARD -i ${TUN_INTERFACE} -o ${WG_INTERFACE} -j ACCEPT

# Drop any VPN subnet traffic going out WAN (prevent bypass)
iptables -A FORWARD -s ${WG_SUBNET} -o ${WAN_INTERFACE} -j DROP
iptables -A OUTPUT  -s ${WG_SUBNET} -o ${WAN_INTERFACE} -j DROP

# (Optional) NAT: Masquerade out tun1 if needed (safety)
iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o ${TUN_INTERFACE} -j MASQUERADE

log "Configuration complete. WireGuard is up on ${WG_INTERFACE}, tun2socks running on ${TUN_INTERFACE}."
