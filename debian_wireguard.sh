#!/bin/bash

function check_root(){
	[[ $EUID != 0 ]] && echo -e "当前账号非ROOT(或没有ROOT权限)，无法继续" && exit 1
}


function check_system(){
cksystem=`uname -a`
case $cksystem in

	*Debian*)
		echo "系统为Debian"
		echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
		apt update
		;;
	*Ubuntu*)
		echo "系统为Ubuntu"
		yes | add-apt-repository ppa:wireguard/wireguard
		;;
	       *)
      		echo '本脚本不支持此操作系统'
		exit 1;
esac
}

check_root
check_system

echo '现在开始安装wireguard...'
yes | apt-get install wireguard-dkms wireguard-tools resolvconf qrencode
yes | apt-get install linux-headers-$(uname -r)

echo '正在配置sysctl.conf'

sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf

sysctl -p

mkdir -p /etc/wireguard && chmod 0777 /etc/wireguard
cd /etc/wireguard
umask 077

wg genkey | tee server_privatekey | wg pubkey > server_publickey
wg genkey | tee client_privatekey | wg pubkey > client_publickey

read -p '请输入服务主机公网ip?  ' net_ip
read -p '请输入服务主机网络接口,例如如eth0?  ' net_eth
read -p '请输入监听端口(数字)?  ' listen_port

echo "
[Interface]
  PrivateKey = $(cat server_privatekey)
  Address = 192.168.100.1/24
  PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $net_eth -j MASQUERADE
  PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $net_eth -j MASQUERADE
  ListenPort = $listen_port
  DNS = 8.8.8.8, 2001:4860:4860::8888
  MTU = 1420

[Peer]
  PublicKey = $(cat client_publickey)
  AllowedIPs = 192.168.100.2/24 " > /etc/wireguard/wg0.conf



echo "
[Interface]
  PrivateKey = $(cat client_privatekey)
  Address = 192.168.100.2/24
  ListenPort = $listen_port
  DNS = 8.8.8.8, 2001:4860:4860::8888
  MTU = 1420

[Peer]
  PublicKey = $(cat server_publickey)
  Endpoint = $net_ip:$listen_port
  AllowedIPs = 0.0.0.0/0, ::0/0
  PersistentKeepalive = 25 " > /etc/wireguard/client.conf

systemctl enable wg-quick@wg0



read -p '已配置完毕,是否生成客户端二维码? [ Y | N ]  ' creat_qrencode

if [ "$creat_qrencode" == "Y" ]  || [ "$creat_qrencode" == "y" ];then
qrencode -t ansiutf8 < /etc/wireguard/client.conf
fi
