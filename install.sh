#!/bin/bash

###############################################################################
# Paqet Tunnel Installer - FOREIGN SERVER (Server Mode)
# Advanced setup with resource detection and optimization options
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Variables
RESOURCE_LEVEL=""
KCP_KEY=""
APPLY_OPTIMIZATION=""

clear
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Paqet Tunnel Installer - FOREIGN/SERVER  ║${NC}"
echo -e "${BLUE}║          Advanced Setup v2.0               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}\n"

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Please run as root (use sudo)${NC}"
    exit 1
fi

###############################################################################
# STEP 1: Install Dependencies
###############################################################################
echo -e "${CYAN}[1/8] Installing dependencies...${NC}"

if command -v apt-get &> /dev/null; then
    apt-get update -qq 2>/dev/null
    apt-get install -y libpcap-dev wget tar curl net-tools iproute2 iptables bc 2>/dev/null || true
elif command -v yum &> /dev/null; then
    yum install -y libpcap-devel wget tar curl net-tools iproute iptables bc 2>/dev/null || true
elif command -v dnf &> /dev/null; then
    dnf install -y libpcap-devel wget tar curl net-tools iproute iptables bc 2>/dev/null || true
else
    echo -e "${YELLOW}Warning: Unknown package manager${NC}"
fi

echo -e "${GREEN}✓ Dependencies installed${NC}\n"

###############################################################################
# STEP 2: Cleanup
###############################################################################
echo -e "${CYAN}[2/8] Cleaning up previous installation...${NC}"

systemctl stop paqet 2>/dev/null || true
systemctl disable paqet 2>/dev/null || true
rm -rf /root/paqet-hub
rm -f /etc/systemd/system/paqet.service
rm -f /tmp/paqet-*.tar.gz

echo -e "${GREEN}✓ Cleanup complete${NC}\n"

###############################################################################
# STEP 3: Server Resources Selection
###############################################################################
echo -e "${CYAN}[3/8] Server Resources Configuration${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Auto-detect resources
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
CPU_CORES=$(nproc)

echo -e "${BLUE}Detected: ${YELLOW}${TOTAL_RAM}GB RAM, ${CPU_CORES} CPU cores${NC}"
echo ""
echo -e "Select server resource profile:"
echo -e "  ${GREEN}1)${NC} High Resources   (≥4GB RAM, ≥4 cores) - Better performance"
echo -e "  ${GREEN}2)${NC} Low Resources    (<4GB RAM, <4 cores) - Resource efficient"
echo ""

# Auto-recommend based on detection
if [ "$TOTAL_RAM" -ge 4 ] && [ "$CPU_CORES" -ge 4 ]; then
    echo -e "${CYAN}→ Recommended: ${GREEN}1 (High)${NC}"
    DEFAULT_RESOURCE="1"
else
    echo -e "${CYAN}→ Recommended: ${YELLOW}2 (Low)${NC}"
    DEFAULT_RESOURCE="2"
fi

read -p "Enter choice [1-2] (default: $DEFAULT_RESOURCE): " RESOURCE_CHOICE
RESOURCE_CHOICE=${RESOURCE_CHOICE:-$DEFAULT_RESOURCE}

case $RESOURCE_CHOICE in
    1)
        RESOURCE_LEVEL="high"
        echo -e "${GREEN}✓ Selected: High Resources${NC}"
        ;;
    2)
        RESOURCE_LEVEL="low"
        echo -e "${GREEN}✓ Selected: Low Resources${NC}"
        ;;
    *)
        echo -e "${RED}Invalid choice, using recommended${NC}"
        RESOURCE_LEVEL=$([ "$DEFAULT_RESOURCE" == "1" ] && echo "high" || echo "low")
        ;;
esac
echo ""

###############################################################################
# STEP 4: Download Binary
###############################################################################
echo -e "${CYAN}[4/8] Downloading paqet binary...${NC}"

cd /root
mkdir -p paqet-hub

# Try official GitHub release first
if wget -q -O /tmp/paqet.tar.gz https://github.com/hanselime/paqet/releases/download/v1.0.0-alpha.12/paqet-linux-amd64-v1.0.0-alpha.12.tar.gz 2>/dev/null; then
    cd /tmp
    tar -xzf paqet.tar.gz 2>/dev/null
    mv paqet_linux_amd64 /root/paqet-hub/paqet 2>/dev/null || true
    rm -f paqet.tar.gz
    cd /root
    echo -e "${GREEN}✓ Downloaded from GitHub${NC}"
else
    # Fallback to alternative source
    echo -e "${YELLOW}→ Trying alternative source...${NC}"
    if wget --content-disposition https://c.linklick.ir/dl/hash/u3lr7owsegplrkol7guzqitl8xnepxjk 2>/dev/null; then
        tar -xzvf paqet-kharej.tar.gz -C /root 2>/dev/null
        rm -f paqet-kharej.tar.gz
        echo -e "${GREEN}✓ Downloaded from alternative source${NC}"
    else
        echo -e "${RED}Error: Failed to download paqet binary${NC}"
        exit 1
    fi
fi

chmod +x /root/paqet-hub/paqet
echo ""

###############################################################################
# STEP 5: Network Auto-Detection
###############################################################################
echo -e "${CYAN}[5/8] Auto-detecting network configuration...${NC}"

# Detect interface
INTERFACE=$(ip route show | grep default | awk '{print $5}' | head -n1)
if [ -z "$INTERFACE" ]; then
    INTERFACE=$(netstat -rn 2>/dev/null | grep '^0.0.0.0' | awk '{print $NF}' | head -n1)
fi
if [ -z "$INTERFACE" ]; then
    echo -e "${YELLOW}Available interfaces:${NC}"
    ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print "  - " $2}'
    read -p "Enter interface name: " INTERFACE
fi

# Detect gateway
GATEWAY=$(ip route show | grep default | awk '{print $3}' | head -n1)
if [ -z "$GATEWAY" ]; then
    GATEWAY=$(netstat -rn 2>/dev/null | grep '^0.0.0.0' | awk '{print $2}' | head -n1)
fi

# Detect local IP (server public IP)
LOCAL_IP=$(ip addr show $INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP=$(ifconfig $INTERFACE 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -n1)
fi
if [ -z "$LOCAL_IP" ]; then
    # Try to get public IP
    LOCAL_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s http://ifconfig.me 2>/dev/null)
fi
if [ -z "$LOCAL_IP" ]; then
    read -p "Enter server public IP address: " LOCAL_IP
fi

# Detect gateway MAC
ping -c 2 $GATEWAY &>/dev/null || true
sleep 1
ROUTER_MAC=$(arp -n $GATEWAY 2>/dev/null | grep -v incomplete | awk 'NR==2{print $3}')
if [ -z "$ROUTER_MAC" ]; then
    ROUTER_MAC=$(ip neigh show $GATEWAY | awk '{print $5}' | head -n1)
fi
if [ -z "$ROUTER_MAC" ]; then
    read -p "Enter gateway MAC address: " ROUTER_MAC
fi

echo -e "${GREEN}✓ Network Configuration:${NC}"
echo -e "  Interface: ${YELLOW}$INTERFACE${NC}"
echo -e "  Server IP: ${YELLOW}$LOCAL_IP${NC}"
echo -e "  Gateway: ${YELLOW}$GATEWAY${NC}"
echo -e "  Gateway MAC: ${YELLOW}$ROUTER_MAC${NC}"
echo ""

###############################################################################
# Get Server Port and KCP Key
###############################################################################
read -p "Enter listen port (default: 444): " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-444}

echo ""
echo -e "${YELLOW}Enter the KCP key from Iran client:${NC}"
read -p "KCP Key (32 characters): " KCP_KEY

# Validate key length
if [ ${#KCP_KEY} -ne 32 ]; then
    echo -e "${YELLOW}⚠ Warning: KCP key should be exactly 32 characters${NC}"
    read -p "Continue anyway? [y/n]: " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Installation cancelled${NC}"
        exit 1
    fi
fi
echo ""

###############################################################################
# STEP 6: Generate Config Based on Selections
###############################################################################
echo -e "${CYAN}[6/8] Generating configuration...${NC}"

# Set transport parameters based on resource level
if [ "$RESOURCE_LEVEL" == "high" ]; then
    CONN_NUM="30"
    KCP_MODE="fast3"
    SNDWND="2048"
    RCVWND="2048"
    SMUXBUF="8388608"
    STREAMBUF="4194304"
else
    CONN_NUM="8"
    KCP_MODE="fast3"
    SNDWND="2048"
    RCVWND="2048"
    SMUXBUF="8388608"
    STREAMBUF="4194304"
fi

# Generate config
cat > /root/paqet-hub/config.yaml <<EOF
# Paqet Server Configuration - FOREIGN
# Generated by installer v2.0
role: "server"

log:
  level: "error"

# Server Listen
listen:
  addr: ":$SERVER_PORT"

# Network Configuration
network:
  interface: "$INTERFACE"
  ipv4:
    addr: "$LOCAL_IP:$SERVER_PORT"
    router_mac: "$ROUTER_MAC"

# Transport Configuration (${RESOURCE_LEVEL^^} resources)
transport:
  protocol: "kcp"
  conn: $CONN_NUM
  kcp:
    mode: "$KCP_MODE"
    block: "aes"
    key: "$KCP_KEY"
    mtu: 1400
    sndwnd: $SNDWND
    rcvwnd: $RCVWND
    smuxbuf: $SMUXBUF
    streambuf: $STREAMBUF
EOF

echo -e "${GREEN}✓ Configuration created${NC}"
echo ""

###############################################################################
# STEP 7: Configure Firewall (iptables)
###############################################################################
echo -e "${CYAN}[7/8] Configuring iptables...${NC}"

# Remove existing rules for this port
iptables -t raw -D PREROUTING -p tcp --dport $SERVER_PORT -j NOTRACK 2>/dev/null || true
iptables -t raw -D OUTPUT -p tcp --sport $SERVER_PORT -j NOTRACK 2>/dev/null || true
iptables -t mangle -D OUTPUT -p tcp --sport $SERVER_PORT --tcp-flags RST RST -j DROP 2>/dev/null || true

# Add new rules
iptables -t raw -A PREROUTING -p tcp --dport $SERVER_PORT -j NOTRACK
iptables -t raw -A OUTPUT -p tcp --sport $SERVER_PORT -j NOTRACK
iptables -t mangle -A OUTPUT -p tcp --sport $SERVER_PORT --tcp-flags RST RST -j DROP

echo -e "${GREEN}✓ iptables configured for port $SERVER_PORT${NC}"

# Save iptables rules
if command -v iptables-save &> /dev/null; then
    if [ -d /etc/iptables ]; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    elif command -v service &> /dev/null; then
        service iptables save 2>/dev/null || true
    fi
fi
echo ""

###############################################################################
# Create Systemd Service
###############################################################################
echo -e "${CYAN}Creating systemd service...${NC}"

cat > /etc/systemd/system/paqet.service <<EOF
[Unit]
Description=Paqet Tunnel Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/paqet-hub
ExecStart=/root/paqet-hub/paqet run -c /root/paqet-hub/config.yaml
Restart=always
RestartSec=10
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable paqet
systemctl start paqet

echo -e "${GREEN}✓ Service created and started${NC}"
echo ""

###############################################################################
# STEP 8: System Optimization (Optional)
###############################################################################
echo -e "${CYAN}[8/8] System Optimization${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Apply system optimizations for better performance?"
echo -e "  - Increase file descriptors"
echo -e "  - Optimize kernel network parameters"
echo -e "  - Enable BBR congestion control"
echo ""
read -p "Apply optimizations? [y/n] (default: y): " APPLY_OPTIMIZATION
APPLY_OPTIMIZATION=${APPLY_OPTIMIZATION:-y}

if [[ "$APPLY_OPTIMIZATION" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}→ Applying optimizations...${NC}"
    
    # File descriptors
    cat >> /etc/security/limits.conf <<EOF
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
    
    # Kernel parameters
    cat > /etc/sysctl.d/99-paqet-performance.conf <<EOF
# Network Performance
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 67108864
net.core.wmem_default = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 500000
net.core.somaxconn = 65535

# TCP Optimization
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535

# Connection Tracking
net.netfilter.nf_conntrack_max = 2000000
net.nf_conntrack_max = 2000000

# UDP
net.ipv4.udp_mem = 262144 524288 1048576
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
EOF
    
    sysctl -p /etc/sysctl.d/99-paqet-performance.conf &>/dev/null || true
    
    # Queue length
    if command -v ifconfig &> /dev/null; then
        ifconfig $INTERFACE txqueuelen 50000 2>/dev/null || true
    else
        ip link set $INTERFACE txqueuelen 50000 2>/dev/null || true
    fi
    
    # Clear cache
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    
    echo -e "${GREEN}✓ Optimizations applied${NC}"
    echo ""
    
    # Reboot recommendation
    echo -e "${YELLOW}⚠ Reboot recommended for optimal performance${NC}"
    read -p "Reboot now? [y/n] (default: n): " REBOOT_NOW
    REBOOT_NOW=${REBOOT_NOW:-n}
    
    if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}→ Rebooting in 5 seconds...${NC}"
        sleep 5
        reboot
        exit 0
    fi
else
    echo -e "${YELLOW}→ Skipped optimizations${NC}"
fi
echo ""

###############################################################################
# Connection Test
###############################################################################
echo -e "${CYAN}Testing service...${NC}"
sleep 3

# Check if service is running
if systemctl is-active --quiet paqet; then
    echo -e "${GREEN}✓ Paqet service is running${NC}"
    
    # Check if port is listening
    if ss -tuln 2>/dev/null | grep -q ":$SERVER_PORT " || netstat -tuln 2>/dev/null | grep -q ":$SERVER_PORT "; then
        echo -e "${GREEN}✓ Port $SERVER_PORT is listening${NC}"
    else
        echo -e "${YELLOW}⚠ Port $SERVER_PORT not found in listening ports${NC}"
        echo -e "${YELLOW}→ This is normal for raw packet mode${NC}"
    fi
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo -e "${YELLOW}→ Check logs: journalctl -u paqet -n 50${NC}"
    echo -e "${YELLOW}→ Try: systemctl daemon-reload && systemctl restart paqet${NC}"
fi
echo ""

###############################################################################
# Final Summary
###############################################################################
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Installation Complete! ✓            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}\n"

echo -e "${BLUE}Configuration Summary:${NC}"
echo -e "  Role: ${YELLOW}Server (Foreign)${NC}"
echo -e "  Resources: ${YELLOW}${RESOURCE_LEVEL^^}${NC}"
echo -e "  Listen Port: ${YELLOW}$SERVER_PORT${NC}"
echo -e "  Server IP: ${YELLOW}$LOCAL_IP${NC}"
echo -e "  KCP Key: ${YELLOW}$KCP_KEY${NC}"
echo ""

echo -e "${BLUE}Service Management:${NC}"
echo -e "  Start:   ${YELLOW}systemctl start paqet${NC}"
echo -e "  Stop:    ${YELLOW}systemctl stop paqet${NC}"
echo -e "  Restart: ${YELLOW}systemctl restart paqet${NC}"
echo -e "  Status:  ${YELLOW}systemctl status paqet${NC}"
echo -e "  Logs:    ${YELLOW}journalctl -u paqet -f${NC}"
echo ""

echo -e "${BLUE}Troubleshooting:${NC}"
echo -e "  ${YELLOW}systemctl daemon-reload${NC}"
echo -e "  ${YELLOW}systemctl restart paqet${NC}"
echo -e "  ${YELLOW}journalctl -u paqet -n 100${NC}"
echo ""

echo -e "${GREEN}Server is ready! Configure Iran client now.${NC}"
