#!/bin/sh

# Run this script on inside/outside host:
# * (outside, do NAT job) set_gre_tunnel.sh out inside 1.1.1.1
# * (inside) set_gre_tunnel.sh in outside 1.1.1.2

function verify_variant() {
    var=$1
    msg=$2 
    if [ x$var != x"" ]; then
        echo $var
        return 0
    fi

    read -p "Can't get $msg, you should assign one manually: " var
    if [ -z $var ]; then
        echo "No $msg assigned." >&2
        exit 1
    fi
    echo $var
    return 0
}

if [ $# -lt 3 ]; then
    echo "Usage $0 in/out remote_host_ip local_tun_ip" >&2
    exit 1
fi

direction=$1
remote_ip=$2
tun_local_ip=$3

tun_name=$(echo $remote_ip | awk -F. '{print $1$2$3$4}')

exit_if=$(ip route | grep default | cut -f5 -d" ")
exit_if=$(verify_variant "$exit_if" "exit interface [$exit_if]")

local_ip=$(ip addr show dev $exit_if | awk 'NR==3 {print $2}' | awk -F/ '{print $1}')
local_ip=$(verify_variant "$local_ip" "local ip address [$local_ip]")

tun_peer_ip=$(echo $tun_local_ip| awk -F. '{printf "%s.%s.%s.%s\n", $1, $2, $3, ($4 % 2 ? $4 + 1 : $4 - 1) }')
tun_peer_ip=$(verify_variant "$tun_peer_ip" "Peer tun ip address [$tun_peer_ip]")

default_gw=$(ip route | grep default | cut -f3 -d" ")
default_gw=$(verify_variant "$default_gw" "Default gateway [$default_gw]")

modprobe ip_gre
ip tun add $tun_name mode gre local $local_ip remote $remote_ip ttl 64 dev $exit_if
ip add add dev $tun_name $tun_local_ip peer $tun_peer_ip/32
ip link set dev $tun_name up

if [ $direction == "in" ]; then
    ip route del 10.0.0.0/8
    ip route add 10.0.0.0/8 via $default_gw
    ip route del default
    ip route add 0.0.0.0/0 via $tun_peer_ip
else
    iptables -A POSTROUTING -t nat -o em1 -j SNAT -s $tun_peer_ip --to-source $local_ip
    echo 1 > /proc/sys/net/ipv4/ip_forward
fi
echo "Done"