#!/bin/bash

set -e

# Usage:
# ./your_script_name.sh \
#   --endpoint <powervc_endpoint> \
#   --project-id <powervc_project_id> \
#   --token YOUR_OPENSTACK_TOKEN \
#   --image-uuid <boot_image_uuid> \
#   --flavor-uuid <machine_spec> \
#   --network-uuid <network_id> \
#   --key-name <vm_ssh_key> \
#   --az <powervc_host_group> \
#   --host-name <powervc_host_name> \
#   --ssh-user <username> \
#   --ssh-key <key_path>\
#   --vm-name <vm_name>
#
# To run in background and save logs:
# nohup ./your_script_name.sh [args here] > your_log_file.log 2>&1 &

# Global vars initialized empty
ENDPOINT=""
PROJECT_ID=""
OS_TOKEN=""
IMAGE_UUID=""
FLAVOR_UUID=""
NETWORK_UUID=""
KEY_NAME=""
AZ=""
HOST_NAME=""
SSH_PRIVATE_KEY=""
SSH_USER=""
VM_NAME=""

parseArgs() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --endpoint) ENDPOINT="$2"; shift ;;
      --project-id) PROJECT_ID="$2"; shift ;;
      --token) OS_TOKEN="$2"; shift ;;
      --image-uuid) IMAGE_UUID="$2"; shift ;;
      --flavor-uuid) FLAVOR_UUID="$2"; shift ;;
      --network-uuid) NETWORK_UUID="$2"; shift ;;
      --key-name) KEY_NAME="$2"; shift ;;
      --az) AZ="$2"; shift ;;
      --host-name) HOST_NAME="$2"; shift ;;
      --ssh-user) SSH_USER="$2"; shift ;;
      --ssh-key) SSH_PRIVATE_KEY="$2"; shift ;;
      --vm-name) VM_NAME="$2"; shift ;;
      --) shift; break ;;
      *) echo "[WARN] Unknown arg: $1"; shift ;;
    esac
    shift
  done
}

test_vm_creation() {
  if [[ -z "$VM_NAME" ]]; then
    VM_NAME="vm-$(date +%s)"
  fi
  local PAYLOAD_FILE="payload_${VM_NAME}.json"

  cat <<EOF > "$PAYLOAD_FILE"
{
  "server": {
    "name": "$VM_NAME",
    "imageRef": "$IMAGE_UUID",
    "flavorRef": "$FLAVOR_UUID",
    "availability_zone": "$AZ",
    "networks": [
      {
        "uuid": "$NETWORK_UUID"
      }
    ],
    "key_name": "$KEY_NAME"
  },
  "OS-SCH-HNT:scheduler_hints": {
    "force_hosts": ["$HOST_NAME"]
  }
}
EOF

  echo "[INFO] Creating VM: $VM_NAME"
  local RESPONSE
  RESPONSE=$(curl -sk -X POST "https://${ENDPOINT}:8774/v2.1/${PROJECT_ID}/servers" \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: ${OS_TOKEN}" \
    -d @"$PAYLOAD_FILE")

  echo "$RESPONSE"

  local VM_ID
  VM_ID=$(echo "$RESPONSE" | sed -n 's/.*"id":[[:space:]]*"\([^"]*\)".*/\1/p')
  if [[ -z "$VM_ID" ]]; then
    echo "[ERROR] VM ID not found in response."
    exit 1
  fi

  echo "[INFO] VM ID: $VM_ID"

  # Poll for IP address
  for i in {1..20}; do
    sleep 5
    local INFO
    INFO=$(curl -sk -X GET "https://${ENDPOINT}:8774/v2.1/${PROJECT_ID}/servers/${VM_ID}" \
      -H "X-Auth-Token: ${OS_TOKEN}")
    local IP
    IP=$(echo "$INFO" | sed -n 's/.*"addr":[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ -n "$IP" ]]; then
      export CREATED_VM_IP="$IP"
      export CREATED_VM_ID="$VM_ID"
      export CREATED_VM_NAME="$VM_NAME"
      echo "[INFO] VM IP Address: $IP"
      return
    fi
    echo "[INFO] Waiting for VM IP... ($i/20)"
  done

  echo "[ERROR] Timeout waiting for VM IP."
  exit 1
}

test_vm_reachability() {
  echo "[INFO] Waiting 15 minutes for VM to reach ACTIVE state before ping test..."
  sleep 900

  echo "[INFO] Pinging VM at $CREATED_VM_IP..."
  ping -c 4 "$CREATED_VM_IP" >/dev/null || {
    echo "[ERROR] Ping to VM failed."
    exit 1
  }

  echo "[INFO] Testing SSH connection..."
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_PRIVATE_KEY" "$SSH_USER@$CREATED_VM_IP" 'echo "[INFO] SSH connection successful."' || {
    echo "[ERROR] SSH connection to VM failed."
    exit 1
  }
}

main() {
  parseArgs "$@"
  test_vm_creation
  test_vm_reachability
}

main "$@"
