#!/usr/bin/env bash

set -e
# set -x

TEMPORARY_DIRECTORY_PATH="$(pwd)/tmp"
VIRTUAL_MACHINES_PATH="${TEMPORARY_DIRECTORY_PATH}/virtual_machines"
CONTROL_PLANE_VMS=()  # Initialize as empty array
WORKER_VMS=()        # Initialize as empty array
SHOULD_DESTROY_VMS="false"

function startup_script() {
  mkdir -p "${TEMPORARY_DIRECTORY_PATH}"
  mkdir -p "${VIRTUAL_MACHINES_PATH}"
}

function cleanup_script() {
  SKIP_CLEANUP_TEMPORARY_DIRECTORY="${SKIP_CLEANUP_TEMPORARY_DIRECTORY:-""}"

  if [[ "${SHOULD_DESTROY_VMS}" == "true" ]]; then
    echo "Cleaning up VMs..." >&2

    # Function to clean up a single VM
    cleanup_vm() {
      local vm="$1"
      echo "Cleaning up VM: ${vm}" >&2

      # Check if VM exists
      if prlctl list "${vm}" &>/dev/null; then
        # Force stop the VM first
        echo "Stopping VM ${vm}..." >&2
        prlctl stop "${vm}" --kill &>/dev/null || true

        # Wait for VM to fully stop - check status in a loop
        local max_wait=30
        local waited=0
        while [[ $waited -lt $max_wait ]]; do
          if ! prlctl status "${vm}" | grep -q "running"; then
            echo "VM ${vm} has stopped" >&2
            break
          fi
          sleep 1
          waited=$((waited + 1))
        done

        # More aggressive cleanup sequence
        echo "Removing VM registration: ${vm}" >&2
        prlctl unregister "${vm}" &>/dev/null || true
        sleep 2  # Give it a moment to unregister

        echo "Deleting VM ${vm} from Parallels..." >&2
        prlctl delete "${vm}" -f &>/dev/null || true
        sleep 2  # Give it a moment to delete

        # Final force cleanup if still registered
        if prlctl list "${vm}" &>/dev/null; then
          echo "Attempting final force cleanup..." >&2
          prlsrvctl remove-registration "${vm}" --force &>/dev/null || true
          rm -rf "/Users/${USER}/Parallels/${vm}.pvm" &>/dev/null || true
        fi

        # Verify VM is completely gone
        if prlctl list "${vm}" &>/dev/null; then
          echo "Warning: VM ${vm} still registered in Parallels" >&2
          return 1
        else
          echo "Successfully removed VM ${vm}" >&2
          return 0
        fi
      fi
    }

    # Clean up control plane VMs
    while read -r vm; do
      [[ -z "${vm}" ]] && continue
      echo "Cleaning up control plane VM: ${vm}" >&2
      cleanup_vm "${vm}"
    done < <(get_vms_from_db "control-plane")

    # Clean up worker VMs
    while read -r vm; do
      [[ -z "${vm}" ]] && continue
      echo "Cleaning up worker VM: ${vm}" >&2
      cleanup_vm "${vm}"
    done < <(get_vms_from_db "workers")

    # Additional cleanup of any leftover VM files
    if [[ -d "${VIRTUAL_MACHINES_PATH}" ]]; then
      rm -rf "${VIRTUAL_MACHINES_PATH}"/*
    fi
  fi

  if [[ -z "${SKIP_CLEANUP_TEMPORARY_DIRECTORY}" ]]; then
    rm -rf "${TEMPORARY_DIRECTORY_PATH}"
  fi

  echo "Cleanup complete" >&2
}

function get_github_latest_release() {
  local owner="${1}"
  local repository="${2}"

  curl -s https://api.github.com/repos/${owner}/${repository}/releases/latest
}

function download_talos_linux() {
  local architecture="${1}"
  local latest_release_json="$(get_github_latest_release siderolabs talos)"
  local filename
  local download_url
  local download_path

  case "${architecture}" in
    "amd64"|"x86_64")
      filename="metal-amd64.iso"
      ;;
    "arm64"|"aarch64")
      filename="metal-arm64.iso"
      ;;
  esac
  download_path="${TEMPORARY_DIRECTORY_PATH}/${filename}"

  if [[ ! -f "${download_path}" ]]; then
    # get the url from the latest release json, filter by filename
    download_url="$(echo "${latest_release_json}" | jq -r ".assets[] | select(.name == \"${filename}\") | .browser_download_url")"

    echo "Downloading ${filename} from ${download_url} to ${download_path}" >&2
    curl -s -L -o "${download_path}" "${download_url}"
  else
    echo "Using cached ${download_path}" >&2
  fi

  echo "${download_path}"
}

function add_vm_to_array() {
    local vm_name="$1"
    local vm_type="$2"

    if [[ "${vm_type}" == "control-plane" ]]; then
        echo "Before adding: CONTROL_PLANE_VMS=${CONTROL_PLANE_VMS[*]}" >&2
        CONTROL_PLANE_VMS+=("${vm_name}")
        echo "After adding: CONTROL_PLANE_VMS=${CONTROL_PLANE_VMS[*]}" >&2
    elif [[ "${vm_type}" == "worker" ]]; then
        echo "Before adding: WORKER_VMS=${WORKER_VMS[*]}" >&2
        WORKER_VMS+=("${vm_name}")
        echo "After adding: WORKER_VMS=${WORKER_VMS[*]}" >&2
    fi
}

function save_vm_to_db() {
    local vm_name="$1"
    local vm_type="$2"
    local db_file="${TEMPORARY_DIRECTORY_PATH}/vms.json"

    # Initialize DB file if it doesn't exist
    if [[ ! -f "${db_file}" ]]; then
        echo '{"control_plane":[],"workers":[]}' > "${db_file}"
    fi

    # Add VM to appropriate array in JSON
    if [[ "${vm_type}" == "control-plane" ]]; then
        jq --arg vm "${vm_name}" '.control_plane += [$vm]' "${db_file}" > "${db_file}.tmp"
    else
        jq --arg vm "${vm_name}" '.workers += [$vm]' "${db_file}" > "${db_file}.tmp"
    fi
    mv "${db_file}.tmp" "${db_file}"
}

function get_vms_from_db() {
    local vm_type="$1"
    local db_file="${TEMPORARY_DIRECTORY_PATH}/vms.json"

    if [[ ! -f "${db_file}" ]]; then
        echo "[]"
        return
    fi

    if [[ "${vm_type}" == "control-plane" ]]; then
        jq -r '.control_plane[]' "${db_file}"
    else
        jq -r '.workers[]' "${db_file}"
    fi
}

function create_parallels_vm() {
  local download_path="${1}"
  local vm_json_config_path="${2}"
  local vm_type="${3}"  # "control-plane" or "worker"
  local vm_name_prefix
  local vm_name
  local vm_cpus
  local vm_memory
  local vm_disk_size
  local vm_network

  if [[ ! -f "${vm_json_config_path}" ]]; then
    echo "VM config file not found: ${vm_json_config_path}" >&2
    exit 1
  fi

  # Add error checking for JSON parsing
  if ! vm_name_prefix="$(jq -r ".name_prefix" "${vm_json_config_path}" 2>/dev/null)"; then
    echo "Error parsing VM config file: Invalid JSON format" >&2
    exit 1
  fi

  # Validate JSON values before proceeding
  if [[ -z "${vm_name_prefix}" || "${vm_name_prefix}" == "null" ]]; then
    echo "Invalid or missing name_prefix in VM config" >&2
    exit 1
  fi

  vm_name="${vm_name_prefix}-$(date +%s)"
  vm_cpus="$(jq -r ".cpus" "${vm_json_config_path}")"
  vm_memory="$(jq -r ".memory" "${vm_json_config_path}")"
  vm_disk_size="$(jq -r ".disk_size" "${vm_json_config_path}")"
  vm_network="$(jq -r ".network" "${vm_json_config_path}")"

  # Validate all required VM parameters
  if [[ -z "${vm_cpus}" || "${vm_cpus}" == "null" || \
        -z "${vm_memory}" || "${vm_memory}" == "null" || \
        -z "${vm_disk_size}" || "${vm_disk_size}" == "null" || \
        -z "${vm_network}" || "${vm_network}" == "null" ]]; then
    echo "Missing required VM configuration parameters" >&2
    exit 1
  fi

  echo "Creating Parallels VM: ${vm_name}" >&2

  # Add error checking for prlctl commands
  if ! prlctl create "${vm_name}" --distribution linux --location "${VIRTUAL_MACHINES_PATH}" >&2; then
    echo "Failed to create VM" >&2
    exit 1
  fi

  # Set VM parameters with error checking
  local prlctl_commands=(
    "prlctl set \"${vm_name}\" --device-bootorder \"cdrom0 hdd0\""
    "prlctl set \"${vm_name}\" --device-set cdrom0 --image \"${download_path}\" --connect"
    "prlctl set \"${vm_name}\" --cpus \"${vm_cpus}\""
    "prlctl set \"${vm_name}\" --memsize \"${vm_memory}\""
    "prlctl set \"${vm_name}\" --device-set hdd0 --size \"${vm_disk_size}\""
    "prlctl set \"${vm_name}\" --device-set net0 --type \"${vm_network}\""
  )

  for cmd in "${prlctl_commands[@]}"; do
    if ! eval "${cmd}" >&2; then
      echo "Failed to configure VM with command: ${cmd}" >&2
      exit 1
    fi
  done

  echo "VM created successfully: ${vm_name}" >&2
  save_vm_to_db "${vm_name}" "${vm_type}"

  echo "${vm_name}"
}

function start_parallels_vm() {
  local vm_name="${1}"

  prlctl start "${vm_name}" >&2
}

function get_vm_ip_address() {
  local vm_name="${1}"
  local max_attempts=10
  local attempt=1
  local ip_address=""

  echo "Waiting for VM IP Address for ${vm_name}" >&2
  while [ $attempt -le $max_attempts ]; do
    echo "Attempt ${attempt}/${max_attempts}" >&2

    # Check if VM is actually running
    if ! prlctl status "${vm_name}" | grep -q "running"; then
      echo "VM is not running yet..." >&2
      sleep 5
      attempt=$((attempt + 1))
      continue
    fi

    # Check network adapter status
    echo "Network adapter status:" >&2
    prlctl list "${vm_name}" -i | grep -A 5 "Network Adapter" >&2

    echo "Checking IP Addresses:" >&2
    prlctl list "${vm_name}" -i | grep "IP Addresses:" >&2

    # Extract IP if available
    ip_address=$(prlctl list "${vm_name}" -i | grep "IP Addresses:" | cut -d":" -f2 | tr ',' '\n' | grep -v "fe80" | grep -v '^[[:space:]]*$' | head -1 | tr -d ' ')

    if [[ -n "${ip_address}" && "${ip_address}" != "null" ]]; then
      echo "IP address found: ${ip_address}" >&2
      echo "${ip_address}"
      return 0
    fi

    echo "No IP address found yet, waiting 10 seconds..." >&2
    sleep 10  # Increased sleep time
    attempt=$((attempt + 1))
  done

  echo "Failed to get VM IP address after ${max_attempts} attempts" >&2
  echo "Please check:" >&2
  echo "1. VM network adapter is properly configured" >&2
  echo "2. DHCP service is running in the network" >&2
  echo "3. VM has successfully booted" >&2
  exit 1
}

function get_cluster_config() {
  local cluster_config_path="${1}"

  if [[ ! -f "${cluster_config_path}" ]]; then
    echo "Cluster config file not found: ${cluster_config_path}" >&2
    exit 1
  fi

  cat "${cluster_config_path}" | jq
}

# Add trap to ensure cleanup on script exit
trap cleanup_script EXIT

function main() {
  local architecture="$(uname -m)"
  local cluster_config_path="./config/cluster.json"
  local cluster_config_json
  local cluster_name
  local control_plane_replicas

  # Set destroy flag to true in case of errors
  SHOULD_DESTROY_VMS="true"

  cluster_config_json="$(get_cluster_config "${cluster_config_path}")"
  cluster_name="$(echo "${cluster_config_json}" | jq -r ".name")"
  control_plane_replicas="$(echo "${cluster_config_json}" | jq -r ".controlPlane.replicas")"

  echo "Bootstrapping Talos Linux Cluster on Parallels with ${control_plane_replicas} control plane nodes" >&2
  startup_script

  iso_download_path="$(download_talos_linux "${architecture}")"

  # Create all control plane nodes
  local first_cp_ip=""
  for ((i=1; i<=control_plane_replicas; i++)); do
    echo "Creating control plane node ${i}/${control_plane_replicas}" >&2
    vm_name="$(create_parallels_vm "${iso_download_path}" "./config/controlplane/parallels.vm.json" "control-plane")"
    start_parallels_vm "${vm_name}"
    vm_ip_address="$(get_vm_ip_address "${vm_name}")"
    echo "VM ${vm_name} IP Address: ${vm_ip_address}" >&2

    # Store first control plane IP for cluster configuration
    if [[ $i -eq 1 ]]; then
      first_cp_ip="${vm_ip_address}"
    fi
  done

  # Generate cluster configurations
  echo "Generating cluster configurations..." >&2
  talosctl gen config "${cluster_name}" "https://${first_cp_ip}:6443"
  mv controlplane.yaml ./tmp/controlplane.yaml
  mv worker.yaml ./tmp/worker.yaml
  mv talosconfig ./tmp/talosconfig

  # Apply configurations to all control plane nodes
  echo "Applying configurations to control plane nodes..." >&2
  cd ./tmp
  while read -r vm; do
    [[ -z "${vm}" ]] && continue
    vm_ip="$(get_vm_ip_address "${vm}")"
    echo "Applying control plane config to ${vm} (${vm_ip})" >&2
    talosctl apply-config --insecure -n "${vm_ip}" --file ./controlplane.yaml
  done < <(get_vms_from_db "control-plane")
  cd -

  # Wait for the control plane to be ready
  echo "Waiting for control plane to be ready..." >&2
  sleep 30

  # Set up talosctl to use the first control plane node
  export TALOSCONFIG="$(pwd)/tmp/talosconfig"
  talosctl config endpoint "${first_cp_ip}"
  talosctl config node "${first_cp_ip}"

  # Bootstrap the cluster
  echo "Bootstrapping the cluster..." >&2
  talosctl bootstrap --insecure --nodes "${first_cp_ip}"

  echo "Cluster bootstrap complete!" >&2
}

# shellcheck disable=SC2068
main ${@}

# talosctl gen config test-cluster https://10.211.55.4:6443
