#!/bin/bash
# Shared helpers for test scripts (Linux + macOS / Docker Desktop).

# Resolve directory of the calling test script's client/ folder.
test_client_dir() {
	local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
	(cd "$(dirname "$src")/../../client" && pwd)
}

# Seed wait-for-connect.sh into a docker volume via stdin (no host bind mount).
seed_client_volume() {
	local img="$1"
	local vol="$2"
	local wait_src="$3"
	docker volume create "$vol" >/dev/null
	docker run --rm -i -v "$vol:/client" "$img" \
		sh -c 'cat > /client/wait-for-connect.sh && chmod +x /client/wait-for-connect.sh' \
		< "$wait_src"
}

# Write client ovpn into volume.
write_client_ovpn() {
	local img="$1"
	local data_vol="$2"
	local client_vol="$3"
	local cn="$4"
	local dest="${5:-config.ovpn}"
	docker run --rm -v "$data_vol:/etc/openvpn" -v "$client_vol:/client" "$img" \
		sh -c "ovpn_getclient \"$cn\" > \"/client/$dest\""
}

# In-place replace host/placeholder IP with container IP inside volume.
rewrite_client_remote() {
	local img="$1"
	local client_vol="$2"
	local from_ip="$3"
	local to_ip="$4"
	local file="${5:-config.ovpn}"
	docker run --rm -v "$client_vol:/client" "$img" \
		sed -i "s:${from_ip}:${to_ip}:g" "/client/$file"
}

# Wait until a named container has an IP.
wait_container_ip() {
	local name="$1"
	local ip=""
	local i
	for i in $(seq 30); do
		# Docker Engine 29+ removed top-level NetworkSettings.IPAddress; read from Networks.
		ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name" 2>/dev/null || true)
		if [ -n "$ip" ]; then
			echo "$ip"
			return 0
		fi
		sleep 0.2
	done
	return 1
}

# Kill background jobs without GNU xargs -r.
kill_jobs() {
	local pids
	pids=$(jobs -p 2>/dev/null || true)
	if [ -n "$pids" ]; then
		# shellcheck disable=SC2086
		kill $pids 2>/dev/null || true
		wait 2>/dev/null || true
	fi
}
