#!/bin/bash
set -e

[ -n "${DEBUG+x}" ] && set -x

OVPN_DATA=dual-data
CLIENT_UDP=travis-client
CLIENT_TCP=travis-client-tcp
IMG=kylemanna/openvpn
# Placeholder only — rewritten to each server container IP before connect.
SERV_IP=10.255.254.1
CLIENT_VOL="dual-client-$$"

# shellcheck source=../helpers.sh
source "$(dirname "$BASH_SOURCE")/../helpers.sh"
CLIENT_DIR="$(test_client_dir)"

cleanup() {
	kill_jobs
	docker rm -f ovpn-test-udp ovpn-test-tcp >/dev/null 2>&1 || true
	docker volume rm -f "$CLIENT_VOL" "$OVPN_DATA" >/dev/null 2>&1 || true
}
trap cleanup EXIT

seed_client_volume "$IMG" "$CLIENT_VOL" "$CLIENT_DIR/wait-for-connect.sh"

docker volume create "$OVPN_DATA" >/dev/null 2>&1 || true

# get temporary TCP config
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_genconfig -u tcp://$SERV_IP:443

# nopass is insecure
docker run -v $OVPN_DATA:/etc/openvpn --rm -e "EASYRSA_BATCH=1" -e "EASYRSA_REQ_CN=Travis-CI Test CA" $IMG ovpn_initpki nopass

# gen TCP client
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG easyrsa build-client-full $CLIENT_TCP nopass
write_client_ovpn "$IMG" "$OVPN_DATA" "$CLIENT_VOL" "$CLIENT_TCP" "config-tcp.ovpn"

# switch to UDP config and gen UDP client
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_genconfig -u udp://$SERV_IP
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG easyrsa build-client-full $CLIENT_UDP nopass
write_client_ovpn "$IMG" "$OVPN_DATA" "$CLIENT_VOL" "$CLIENT_UDP" "config.ovpn"

#Verify client configs
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_listclients | grep $CLIENT_TCP
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_listclients | grep $CLIENT_UDP

#
# Fire up the server
#
docker run --name "ovpn-test-udp" -v $OVPN_DATA:/etc/openvpn --rm --cap-add=NET_ADMIN -e DEBUG $IMG &
docker run --name "ovpn-test-tcp" -v $OVPN_DATA:/etc/openvpn --rm --cap-add=NET_ADMIN -e DEBUG $IMG ovpn_run --proto tcp --port 443 &

SERV_IP_UDP="$(wait_container_ip ovpn-test-udp)"
rewrite_client_remote "$IMG" "$CLIENT_VOL" "$SERV_IP" "$SERV_IP_UDP" "config.ovpn"

SERV_IP_TCP="$(wait_container_ip ovpn-test-tcp)"
rewrite_client_remote "$IMG" "$CLIENT_VOL" "$SERV_IP" "$SERV_IP_TCP" "config-tcp.ovpn"

#
# Fire up clients in containers since openvpn is disallowed by Travis-CI
#
docker run --rm --cap-add=NET_ADMIN -v $CLIENT_VOL:/client -e DEBUG $IMG /client/wait-for-connect.sh
docker run --rm --cap-add=NET_ADMIN -v $CLIENT_VOL:/client -e DEBUG $IMG /client/wait-for-connect.sh "/client/config-tcp.ovpn"

#
# Celebrate
#
cat <<EOF
 ____________               ___________
< it worked! >             < both ways! >
 ------------               ------------
        \   ^__^        ^__^   /
	 \  (oo)\______/(oo)  /
	    (__)\      /(__)
                ||w---w||
                ||     ||
EOF
