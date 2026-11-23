#!/bin/bash
set -e

[ -n "${DEBUG+x}" ] && set -x

OVPN_DATA=basic-data
CLIENT=travis-client
IMG=kylemanna/openvpn
# Placeholder only — rewritten to the server container IP before connect.
SERV_IP=10.255.254.1
CLIENT_VOL="basic-client-$$"

# shellcheck source=../helpers.sh
source "$(dirname "$BASH_SOURCE")/../helpers.sh"
CLIENT_DIR="$(test_client_dir)"

cleanup() {
	kill_jobs
	docker rm -f ovpn-test >/dev/null 2>&1 || true
	docker volume rm -f "$CLIENT_VOL" >/dev/null 2>&1 || true
}
trap cleanup EXIT

seed_client_volume "$IMG" "$CLIENT_VOL" "$CLIENT_DIR/wait-for-connect.sh"

docker volume create "$OVPN_DATA" >/dev/null 2>&1 || true
docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_genconfig -u udp://$SERV_IP

# nopass is insecure
docker run -v $OVPN_DATA:/etc/openvpn --rm -e "EASYRSA_BATCH=1" -e "EASYRSA_REQ_CN=Travis-CI Test CA" $IMG ovpn_initpki nopass

docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG easyrsa build-client-full $CLIENT nopass

write_client_ovpn "$IMG" "$OVPN_DATA" "$CLIENT_VOL" "$CLIENT"

docker run -v $OVPN_DATA:/etc/openvpn --rm $IMG ovpn_listclients | grep $CLIENT

#
# Fire up the server
#
docker run --name "ovpn-test" -v $OVPN_DATA:/etc/openvpn --rm -e DEBUG --cap-add=NET_ADMIN $IMG &

SERV_IP_INTERNAL="$(wait_container_ip ovpn-test)"
rewrite_client_remote "$IMG" "$CLIENT_VOL" "$SERV_IP" "$SERV_IP_INTERNAL"

#
# Fire up a client in a container since openvpn is disallowed by Travis-CI
#
docker run --rm --cap-add=NET_ADMIN -e DEBUG -v $CLIENT_VOL:/client $IMG /client/wait-for-connect.sh

#
# Celebrate
#
cat <<EOF
 ___________
< it worked >
 -----------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\\
                ||----w |
                ||     ||
EOF
