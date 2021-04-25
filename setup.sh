#!/bin/bash
#################################################################
# Janus installation script
# Author: Daniil Makeev / daniil-makeev@yandex.ru
# Date: 19.04.2021
#################################################################

# SSL certificate
USE_SSL=true
CERT_PATH='/opt/cert/fullchain.pem'
PKEY_PATH='/opt/cert/privkey.pem'
# Stun settings
STUN_IP='stun.l.google.com'
STUN_PORT=19302
# Turn settings
USE_TURN=false
TURN_IP=''
TURN_PORT=''
TURN_USER=''
TURN_CREDENTIAL=''
# Janus ports for http and ws
ENABLE_HTTP=true
PORT_HTTP=8880
ENABLE_WS=true
PORT_WS=8870
# Security token - generate a random if empty string is passed
TOKEN=''
# Janus branch to fetch
JANUS_BRANCH='multistream' # 'master' by default

############################################################
# Install dependencies
############################################################
# Install all required for Janus
add-apt-repository universe
apt-get update
apt-get upgrade -y
apt-get install software-properties-common -y

apt-get install libmicrohttpd-dev libjansson-dev libssl-dev libsofia-sip-ua-dev \
	libglib2.0-dev libopus-dev libogg-dev libcurl4-openssl-dev \
    liblua5.3-dev libconfig-dev pkg-config gengetopt libtool automake \
    gtk-doc-tools libavutil-dev libavcodec-dev \
    libavformat-dev git curl cmake build-essential -y

# Install libnice
apt-get install python3 python3-pip python3-setuptools \
                       python3-wheel ninja-build -y
pip3 install meson
git clone https://gitlab.freedesktop.org/libnice/libnice libnice
cd libnice
meson --prefix=/usr build && ninja -C build && sudo ninja -C build install
cd ..

# Install libsrtp

wget https://github.com/cisco/libsrtp/archive/v2.2.0.tar.gz
tar xfv v2.2.0.tar.gz
cd libsrtp-2.2.0
./configure --prefix=/usr --enable-openssl
make shared_library && sudo make install
cd ..


# Install libwebsockets
git clone https://libwebsockets.org/repo/libwebsockets libwebsockets
cd libwebsockets
# If you want the stable version of libwebsockets, uncomment the next line
# git checkout v3.2-stable
mkdir build
cd build
# See https://github.com/meetecho/janus-gateway/issues/732 re: LWS_MAX_SMP
# See https://github.com/meetecho/janus-gateway/issues/2476 re: LWS_WITHOUT_EXTENSIONS
cmake -DLWS_MAX_SMP=1 -DLWS_WITHOUT_EXTENSIONS=0 -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_C_FLAGS="-fpic" ..
make && sudo make install
cd ../..

# Install Node.js
curl -sL https://deb.nodesource.com/setup_14.x -o nodesource_setup.sh
sudo bash ./nodesource_setup.sh
sudo apt install nodejs

############################################################
# Fetch and install Janus
############################################################
git clone -b ${JANUS_BRANCH} https://github.com/meetecho/janus-gateway.git janus-gateway
cd janus-gateway
sh ./autogen.sh
./configure --prefix=/opt/janus --disable-data-channels --disable-rabbitmq --disable-mqtt --disable-unix-sockets --enable-post-processing --disable-aes-gcm --enable-all-js-modules
make && make install && 
make configs
cd ..

# Remove installation files
rm -rf janus-gateway
rm -rf libnice
rm -rf libsrtp-2.2.0
rm -rf libwebsockets
rm -f  v2.2.0.tar.gz
rm -f  nodesource_setup.sh

# Create system service for Janus
echo "[Unit]
Description=Janus media server
After=network.target

[Service]
Type=simple
ExecStart=/opt/janus/bin/janus
ExecStartPre=-/bin/sed -i.bak -re \"s/#*interface = \\\"[^\\\"]*\\\"/interface = \\\"$(wget -qO- ifconfig.me/ip)\\\"/\" /opt/janus/etc/janus/janus.jcfg
ExecStartPre=-/bin/sed -i.bak -re \"s/#*nat_1_1_mapping = \\\"[^\\\"]*\\\"/nat_1_1_mapping = \\\"$(wget -qO- ifconfig.me/ip)\\\"/\" /opt/janus/etc/janus/janus.jcfg
ExecStartPre=-/bin/rm /opt/janus/etc/janus/*.bak
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/janus.service

# /bin/sed -i.bak -re "s/#*interface = \"[^\"]*\"/interface = "$(wget -qO- ifconfig.me/ip)\/\" /opt/janus/etc/janus/janus.jcfg

############################################################
# Configure Janus
############################################################

# Generate security token for Janus, if emptu token was set
if [ -z $TOKEN ]; then
    TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
fi

# HTTP endpoing
if $ENABLE_HTTP; then
    if $USE_SSL; then
        sed -i.bak -re "s/http = true/http = false/" /opt/janus/etc/janus/janus.transport.http.jcfg
        sed -i.bak -re "s/https = false/https = true/" /opt/janus/etc/janus/janus.transport.http.jcfg
        sed -i.bak -re "s/#secure_port = [0-9]*/secure_port = ${PORT_HTTP}/" /opt/janus/etc/janus/janus.transport.http.jcfg
        sed -i.bak -re "s/#cert_pem = \"[^\"]*\"/cert_pem = \"${CERT_PATH//\//\\/}\"/" /opt/janus/etc/janus/janus.transport.http.jcfg
        sed -i.bak -re "s/#cert_key = \"[^\"]*\"/cert_key = \"${PKEY_PATH//\//\\/}\"/" /opt/janus/etc/janus/janus.transport.http.jcfg
    else
        sed -i.bak -re "s/port = [0-9]*/port = ${PORT_HTTP}/" /opt/janus/etc/janus/janus.transport.http.jcfg
    fi
else
    sed -i.bak -re "s/http = true/http = false/" /opt/janus/etc/janus/janus.transport.http.jcfg
fi

# Websocket config
if $ENABLE_WS; then
    if $USE_SSL; then
        sed -i.bak -re "s/ ws = true/ ws = false/" /opt/janus/etc/janus/janus.transport.websockets.jcfg
        sed -i.bak -re "s/ wss = false/ wss = true/" /opt/janus/etc/janus/janus.transport.websockets.jcfg
        sed -i.bak -re "s/#wss_port = [0-9]*/wss_port = ${PORT_WS}/" /opt/janus/etc/janus/janus.transport.websockets.jcfg
        sed -i.bak -re "s/#cert_pem = \"[^\"]*\"/cert_pem = \"${CERT_PATH//\//\\/}\"/" /opt/janus/etc/janus/janus.transport.websockets.jcfg
        sed -i.bak -re "s/#cert_key = \"[^\"]*\"/cert_key = \"${PKEY_PATH//\//\\/}\"/" /opt/janus/etc/janus/janus.transport.websockets.jcfg
    else
        sed -i.bak -re "s/ws_port = [0-9]*/ws_port = ${PORT_WS}/" /opt/janus/etc/janus/janus.transport.websockets.jcfg
    fi
else
    sed -i.bak -re "s/ws = true/ws = false/" /opt/janus/etc/janus/janus.transport.websockets.jcfg
fi

# Main config
sed -i.bak -re "s/#api_secret = \"[^\"]*\"/api_secret = \"${TOKEN}\"/" /opt/janus/etc/janus/janus.jcfg
sed -i.bak -re "s/#ipv6 = true/ipv6 = false/" /opt/janus/etc/janus/janus.jcfg
# sed -ire "s/#rtp_port_range = \"[^\"]*\"/rtp_port_range = \"49152\-65535\"/" /opt/janus/etc/janus/janus.jcfg
sed -i.bak -re "s/#full_trickle = true/full_trickle = false/" /opt/janus/etc/janus/janus.jcfg
sed -i.bak -re "s/#ice_lite = true/ice_lite = true/" /opt/janus/etc/janus/janus.jcfg
sed -i.bak -re "s/#stun_server = \"[^\"]*\"/stun_server = \"${STUN_IP}\"/" /opt/janus/etc/janus/janus.jcfg
sed -i.bak -re "s/#stun_port = [0-9]*/stun_port = ${STUN_PORT}/" /opt/janus/etc/janus/janus.jcfg

if $USE_TURN; then
    sed -i.bak -re "s/#turn_server = \"[^\"]*\"/turn_server = \"${TURN_IP}\"/" /opt/janus/etc/janus/janus.jcfg
    sed -i.bak -re "s/#turn_port = [0-9]*/turn_port = ${TURN_PORT}/" /opt/janus/etc/janus/janus.jcfg
    sed -i.bak -re "s/#turn_user = \"[^\"]*\"/turn_user = ${TURN_USER}/" /opt/janus/etc/janus/janus.jcfg
    sed -i.bak -re "s/#turn_pwd = \"[^\"]*\"/turn_pwd = ${TURN_CREDENTIAL}/" /opt/janus/etc/janus/janus.jcfg
fi

if $USE_SSL; then
    sed -i.bak -re "s/#cert_pem = \"[^\"]*\"/cert_pem = \"${CERT_PATH//\//\\/}\"/" /opt/janus/etc/janus/janus.jcfg
    sed -i.bak -re "s/#cert_key = \"[^\"]*\"/cert_key = \"${PKEY_PATH//\//\\/}\"/" /opt/janus/etc/janus/janus.jcfg
fi

# Remove SED backup files
rm /opt/janus/etc/janus/*.bak

# Start Janus service
systemctl daemon-reload
sudo systemctl enable janus
sudo service janus start

echo "################################################"
echo "# Done, Janus API token ${TOKEN}"
echo "################################################"
