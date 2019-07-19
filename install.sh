#!/bin/bash

source /etc/lsb-release
export PUBLIC_IP=$(curl -s 169.254.169.254/latest/meta-data/public-ipv4)
export NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
export CIPHER="AES-128-GCM"
export CERT_CURVE="prime256v1"
export CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
export DH_CURVE="prime256v1"
export HMAC_ALG="SHA256"
export DH_KEY_SIZE="1024"
export EASYRSA_CRL_DAYS="365"
export SERVER_CN="cn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
export SERVER_NAME="openvpn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"

apt-get update
apt-get -y install ca-certificates gnupg
echo "deb http://build.openvpn.net/debian/openvpn/stable $DISTRIB_CODENAME main" > /etc/apt/sources.list.d/openvpn.list
wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
apt-get update
apt-get install -y openvpn iptables openssl wget ca-certificates curl

# Install the latest version of easy-rsa from source
version="3.0.6"
rm -rf /etc/openvpn/easy-rsa/
wget -O /tmp/EasyRSA-unix-v${version}.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v${version}/EasyRSA-unix-v${version}.tgz
tar xzf /tmp/EasyRSA-unix-v${version}.tgz -C /tmp/
mv /tmp/EasyRSA-v${version} /etc/openvpn/easy-rsa
chown -R root:root /etc/openvpn/easy-rsa/
rm -f /tmp/EasyRSA-unix-v${version}.tgz

cd /etc/openvpn/easy-rsa/
cat << EOF > vars
set_var EASYRSA_ALGO ec
set_var EASYRSA_CURVE prime256v1
set_var EASYRSA_KEY_SIZE 4096
set_var EASYRSA_REQ_CN ${SERVER_CN}
EOF
./easyrsa init-pki
./easyrsa --batch build-ca nopass
rm -f ~/.rnd
openssl dhparam -out dh.pem ${DH_KEY_SIZE}
./easyrsa build-server-full "${SERVER_NAME}" nopass
./easyrsa gen-crl
openvpn --genkey --secret /etc/openvpn/tls-crypt.key

# Move all the generated files
cp pki/ca.crt pki/private/ca.key "pki/issued/${SERVER_NAME}.crt" "pki/private/${SERVER_NAME}.key" pki/crl.pem dh.pem /etc/openvpn

# Make cert revocation list readable for non-root
chmod 644 /etc/openvpn/crl.pem
chmod 400 /etc/openvpn/*.{crt,key}
mkdir -p /var/log/openvpn
chown nobody:nogroup /var/log/openvpn
chmod 755 /var/log/openvpn

echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.d/20-openvpn.conf
sysctl --system > /dev/null

# Add iptables rules in two scripts
mkdir -p /etc/iptables

# Script to add rules
cat << EOF > /etc/iptables/add-openvpn-rules.sh
#!/bin/sh
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${NIC} -j MASQUERADE
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i ${NIC} -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o ${NIC} -j ACCEPT
iptables -A INPUT -i ${NIC} -p udp --dport 1194 -j ACCEPT
EOF

chmod +x /etc/iptables/add-openvpn-rules.sh
/etc/iptables/add-openvpn-rules.sh

cat << EOF > /etc/openvpn/server.conf
port 1194
proto udp
dev tun
user nobody
group nogroup
persist-key
persist-tun
keepalive 10 120
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "dhcp-option DNS 127.0.0.1"
push "redirect-gateway def1 bypass-dhcp"
dh dh.pem
ecdh-curve prime256v1
tls-crypt tls-crypt.key 0
crl-verify crl.pem
ca ca.crt
cert ${SERVER_NAME}.crt
key ${SERVER_NAME}.key
auth SHA256
cipher AES-128-GCM
ncp-ciphers AES-128-GCM
tls-server
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256
status /var/log/openvpn/status.log
verb 3
EOF

service openvpn restart


cat << EOF > ~/mission_${PUBLIC_IP}.ovpn
client
proto udp
remote ${PUBLIC_IP} 1194
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verify-x509-name ${SERVER_NAME} name
auth SHA256
auth-nocache
cipher AES-128-GCM
tls-client
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256
setenv opt block-outside-dns
verb 3
<ca>
$(cat /etc/openvpn/easy-rsa/pki/ca.crt)
</ca>
<cert>
$(awk '/BEGIN/,/END/' "/etc/openvpn/easy-rsa/pki/issued/${SERVER_NAME}.crt")
</cert>
<key>
$(cat /etc/openvpn/easy-rsa/pki/private/${SERVER_NAME}.key)
</key>
<tls-crypt>
$(cat /etc/openvpn/tls-crypt.key)
</tls-crypt>
EOF
