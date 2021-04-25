# Janus media server installation script

## Parameters (can be found at the beginning of the script)
* USE_SSL - if SSL should be enabled
* CERT_PATH - path to SSL certificate file, if SSL is enabled 
* PKEY_PATH - path to SSL private key file, if SSL is enabled
* STUN_IP - STUN server IP or hostname
* STUN_PORT - STUN port
* USE_TURN - if TURN server should be used
* TURN_IP - TURN server IP or hostname, if TURN is enabled
* TURN_PORT - TURN server port
* TURN_USER - TURN username
* TURN_CREDENTIAL - TURN password
* ENABLE_HTTP - if HTTP(s) endpoint should be enabled
* PORT_HTTP - HTTP(S) port
* ENABLE_WS - if WS(S) endpoint should be enabled
* PORT_WS - WS(S) port
* TOKEN - Janus security token, will be generated if empty string is passed
* JANUS_BRANCH - what branch of Janus should be fetched

## What differs from the original Janus config
* IPV6 is disabled
* Full trickle ICE is disabled
* ICE lite is enabled
* Current server IP is hardcoded to nat_1_1_mapping interface parameters. Those values are updated by systemd service on service start