#!/bin/bash
set -e

[ -n "${DEBUG+x}" ] && set -x

OVPN_DATA="ovpn-revoke-test-data"
CLIENT1="travis-client1"
CLIENT2="travis-client2"
IMG="kylemanna/openvpn"
NAME="ovpn-revoke-test"
# Placeholder only — rewritten to the server container IP before connect.
SERV_IP=10.255.254.1
CLIENT_VOL="revoke-client-$$"

# shellcheck source=../helpers.sh
source "$(dirname "$BASH_SOURCE")/../helpers.sh"
CLIENT_DIR="$(test_client_dir)"

#
# Initialize openvpn configuration and pki.
#
docker volume rm -f $OVPN_DATA >/dev/null 2>&1 || true
docker volume create --name $OVPN_DATA
seed_client_volume "$IMG" "$CLIENT_VOL" "$CLIENT_DIR/wait-for-connect.sh"
docker run --rm -v $OVPN_DATA:/etc/openvpn $IMG ovpn_genconfig -u udp://$SERV_IP
docker run --rm -v $OVPN_DATA:/etc/openvpn -e "EASYRSA_BATCH=1" -e "EASYRSA_REQ_CN=Travis-CI Test CA" $IMG ovpn_initpki nopass

# Register clean-up function
function finish {
	docker rm -f $NAME >/dev/null 2>&1 || true
	docker volume rm -f $OVPN_DATA "$CLIENT_VOL" >/dev/null 2>&1 || true
	kill_jobs
}
trap finish EXIT

# Put the server in the background
docker run -d -v $OVPN_DATA:/etc/openvpn --cap-add=NET_ADMIN --name $NAME $IMG

#
# Test that easy_rsa generate CRLs with 'next publish' set to 3650 days.
# Parse nextUpdate inside the container with BusyBox date -D (GNU/BSD host date differ).
#
crl_remain="$(docker exec $NAME sh -c '
	next=$(openssl crl -nextupdate -noout -in "$EASYRSA_PKI/crl.pem" | cut -d= -f2-)
	next_s=$(date -u -D "%b %d %H:%M:%S %Y %Z" -d "$next" +%s)
	now=$(date +%s)
	echo $(( (next_s - now) / 86400 ))
')"
if (( crl_remain < 3649 )); then
	echo "easy_rsa CRL next publish set to less than 3650 days (remain=${crl_remain})." >&2
	exit 2
fi

#
# Generate a first client certificate and configuration using $CLIENT1 as CN then revoke it.
#
docker exec $NAME easyrsa build-client-full $CLIENT1 nopass
write_client_ovpn "$IMG" "$OVPN_DATA" "$CLIENT_VOL" "$CLIENT1"
docker exec $NAME bash -c "echo 'yes' | ovpn_revokeclient $CLIENT1"

SERV_IP_INTERNAL="$(wait_container_ip "$NAME")"
rewrite_client_remote "$IMG" "$CLIENT_VOL" "$SERV_IP" "$SERV_IP_INTERNAL"

#
# Test that openvpn client can't connect using $CLIENT1 config.
#
if docker run --rm -v $CLIENT_VOL:/client --cap-add=NET_ADMIN -e DEBUG $IMG /client/wait-for-connect.sh; then
	echo "Client was able to connect after revocation test #1." >&2
	exit 2
fi

#
# Generate and revoke a second client certificate using $CLIENT2 as CN, then test for failed client connection.
#
docker exec $NAME easyrsa build-client-full $CLIENT2 nopass
write_client_ovpn "$IMG" "$OVPN_DATA" "$CLIENT_VOL" "$CLIENT2"
docker exec $NAME bash -c "echo 'yes' | ovpn_revokeclient $CLIENT2"

SERV_IP_INTERNAL="$(wait_container_ip "$NAME")"
rewrite_client_remote "$IMG" "$CLIENT_VOL" "$SERV_IP" "$SERV_IP_INTERNAL"

if docker run --rm -v $CLIENT_VOL:/client --cap-add=NET_ADMIN -e DEBUG $IMG /client/wait-for-connect.sh; then
	echo "Client was able to connect after revocation test #2." >&2
	exit 2
fi

#
# Restart the server
#
docker stop $NAME && docker start $NAME

#
# Test for failed connection using $CLIENT2 config again.
#
if docker run --rm -v $CLIENT_VOL:/client --cap-add=NET_ADMIN -e DEBUG $IMG /client/wait-for-connect.sh; then
	echo "Client was able to connect after revocation test #3." >&2
	exit 2
fi

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
