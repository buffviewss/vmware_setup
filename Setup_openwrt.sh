#!/bin/bash

# Thiết lập WAN và LAN cho OpenWRT

# WAN nhận DHCP từ pfSense
uci set network.wan=interface
uci set network.wan.proto='dhcp'   # Đặt WAN sử dụng DHCP
uci set network.wan.ifname='eth1'  # Thay 'eth1' bằng giao diện phù hợp
uci commit network
/etc/init.d/network restart

# LAN 192.168.50.1/24 (bridge br-lan)
uci set network.lan.device='br-lan'
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.50.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network
/etc/init.d/network restart

# Bật DHCP cho LAN (phát IP cho VM con)
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='101'          # 192.168.50.100–200
uci set dhcp.lan.leasetime='12h'
uci commit dhcp
/etc/init.d/dnsmasq restart

# Tùy chọn: Tắt IPv6 nếu node proxy không hỗ trợ IPv6
uci set network.wan.ipv6='0'
uci set network.lan.ip6assign='0'
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ndp='disabled'
uci commit network; uci commit dhcp
/etc/init.d/network restart
/etc/init.d/dnsmasq restart

# Bật SSH
/etc/init.d/dropbear enable
/etc/init.d/dropbear start

# Thông báo sau khi script chạy thành công
LAN_IP=$(uci get network.lan.ipaddr)
echo "Script completed!"
echo "Your IP LAN : $LAN_IP"
