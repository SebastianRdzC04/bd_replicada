#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
KEY_FILE="${ROOT_DIR}/mongo.key"
NODE_DIRS=("${ROOT_DIR}/node1" "${ROOT_DIR}/node2" "${ROOT_DIR}/node3")

if [[ ! -f "${ENV_FILE}" ]]; then
  printf 'No existe %s\n' "${ENV_FILE}" >&2
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

required_vars=(
  MONGO_IMAGE
  MONGO_REPLICA_SET_NAME
  MONGO_ROOT_USERNAME
  MONGO_ROOT_PASSWORD
  MONGO_NODE1_HOST
  MONGO_NODE1_ADDRESS
  MONGO_NODE1_PORT
  MONGO_NODE1_NAME
  MONGO_NODE2_HOST
  MONGO_NODE2_ADDRESS
  MONGO_NODE2_PORT
  MONGO_NODE2_NAME
  MONGO_NODE3_HOST
  MONGO_NODE3_ADDRESS
  MONGO_NODE3_PORT
  MONGO_NODE3_NAME
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    printf 'La variable %s es obligatoria\n' "${var_name}" >&2
    exit 1
  fi
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Falta el comando requerido: %s\n' "$1" >&2
    exit 1
  fi
}

docker_compose() {
  docker compose --env-file "${ENV_FILE}" --project-directory "$1" -f "$1/docker-compose.yml" "$2" "${@:3}"
}

mongo_eval_noauth() {
  local container_name="$1"
  local port="$2"
  local script="$3"

  docker exec -i \
    -e MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME}" \
    -e MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD}" \
    "${container_name}" \
    mongosh --quiet --port "${port}" --eval "${script}"
}

mongo_eval_auth() {
  local container_name="$1"
  local port="$2"
  local script="$3"

  docker exec -i \
    -e MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME}" \
    -e MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD}" \
    "${container_name}" \
    mongosh --quiet --port "${port}" \
      --username "${MONGO_ROOT_USERNAME}" \
      --password "${MONGO_ROOT_PASSWORD}" \
      --authenticationDatabase admin \
      --eval "${script}"
}

wait_for_mongo() {
  local container_name="$1"
  local port="$2"
  local attempts=60

  while (( attempts > 0 )); do
    if mongo_eval_noauth "${container_name}" "${port}" 'db.adminCommand({ ping: 1 }).ok' 2>/dev/null | grep -qx '1'; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  printf 'MongoDB no respondió en el contenedor %s puerto %s\n' "${container_name}" "${port}" >&2
  return 1
}

wait_for_container_health() {
  local container_name="$1"
  local attempts=60
  local status

  while (( attempts > 0 )); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "${container_name}" 2>/dev/null || true)"
    if [[ "${status}" == "healthy" ]]; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  printf 'El contenedor %s no reportó estado healthy\n' "${container_name}" >&2
  return 1
}

wait_for_primary() {
  local attempts=60

  while (( attempts > 0 )); do
    if mongo_eval_noauth "${MONGO_NODE1_NAME}" "${MONGO_NODE1_PORT}" 'db.hello().isWritablePrimary ? "primary" : "waiting"' 2>/dev/null | grep -qx 'primary'; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 2
  done

  printf 'No se eligió un primary a tiempo\n' >&2
  return 1
}

ensure_keyfile() {
  if [[ ! -f "${KEY_FILE}" ]]; then
    openssl rand -base64 756 > "${KEY_FILE}"
    chmod 400 "${KEY_FILE}"
  fi

  chmod 400 "${KEY_FILE}"

  for node_dir in "${NODE_DIRS[@]}"; do
    if [[ -d "${node_dir}/mongo.key" ]]; then
      rm -rf "${node_dir}/mongo.key"
    fi
    install -m 400 "${KEY_FILE}" "${node_dir}/mongo.key"
  done
}

start_nodes() {
  for node_dir in "${NODE_DIRS[@]}"; do
    mkdir -p "${node_dir}/data"
    docker_compose "${node_dir}" up -d
  done
}

wait_for_all_nodes() {
  wait_for_container_health "${MONGO_NODE1_NAME}"
  wait_for_container_health "${MONGO_NODE2_NAME}"
  wait_for_container_health "${MONGO_NODE3_NAME}"
  wait_for_mongo "${MONGO_NODE1_NAME}" "${MONGO_NODE1_PORT}"
  wait_for_mongo "${MONGO_NODE2_NAME}" "${MONGO_NODE2_PORT}"
  wait_for_mongo "${MONGO_NODE3_NAME}" "${MONGO_NODE3_PORT}"
}

initiate_replicaset() {
  local rs_status

  rs_status="$(mongo_eval_auth "${MONGO_NODE1_NAME}" "${MONGO_NODE1_PORT}" 'rs.status().ok' 2>/dev/null || true)"
  if grep -qx '1' <<<"${rs_status}"; then
    printf 'Replica set ya inicializado\n'
    return 0
  fi

  rs_status="$(mongo_eval_noauth "${MONGO_NODE1_NAME}" "${MONGO_NODE1_PORT}" 'try { rs.status().ok } catch (error) { print("not_initiated") }' 2>/dev/null || true)"

  if grep -qx '1' <<<"${rs_status}"; then
    printf 'Replica set ya inicializado\n'
    return 0
  fi

  if ! grep -qx 'not_initiated' <<<"${rs_status}"; then
    printf 'Estado inesperado del replica set: %s\n' "${rs_status}" >&2
    return 1
  fi

  docker exec -i \
    -e MONGO_REPLICA_SET_NAME="${MONGO_REPLICA_SET_NAME}" \
    -e MONGO_NODE1_HOST="${MONGO_NODE1_HOST}" \
    -e MONGO_NODE1_PORT="${MONGO_NODE1_PORT}" \
    -e MONGO_NODE2_HOST="${MONGO_NODE2_HOST}" \
    -e MONGO_NODE2_PORT="${MONGO_NODE2_PORT}" \
    -e MONGO_NODE3_HOST="${MONGO_NODE3_HOST}" \
    -e MONGO_NODE3_PORT="${MONGO_NODE3_PORT}" \
    "${MONGO_NODE1_NAME}" \
    mongosh --quiet --port "${MONGO_NODE1_PORT}" <<EOF
rs.initiate({
  _id: process.env.MONGO_REPLICA_SET_NAME,
  members: [
    { _id: 0, host: process.env.MONGO_NODE1_HOST + ':' + process.env.MONGO_NODE1_PORT, priority: 2 },
    { _id: 1, host: process.env.MONGO_NODE2_HOST + ':' + process.env.MONGO_NODE2_PORT, priority: 1 },
    { _id: 2, host: process.env.MONGO_NODE3_HOST + ':' + process.env.MONGO_NODE3_PORT, priority: 1 }
  ]
})
EOF
}

ensure_admin_user() {
  local user_exists

  user_exists="$(mongo_eval_auth "${MONGO_NODE1_NAME}" "${MONGO_NODE1_PORT}" 'db.getSiblingDB("admin").getUser(process.env.MONGO_ROOT_USERNAME) ? "yes" : "no"' 2>/dev/null || true)"
  if grep -qx 'yes' <<<"${user_exists}"; then
    printf 'Usuario administrador ya existe\n'
    return 0
  fi

  docker exec -i \
    -e MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME}" \
    -e MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD}" \
    "${MONGO_NODE1_NAME}" \
    mongosh --quiet --port "${MONGO_NODE1_PORT}" <<EOF
db = db.getSiblingDB('admin')
db.createUser({
  user: process.env.MONGO_ROOT_USERNAME,
  pwd: process.env.MONGO_ROOT_PASSWORD,
  roles: [
    { role: 'root', db: 'admin' }
  ]
})
EOF

  user_exists="$(mongo_eval_auth "${MONGO_NODE1_NAME}" "${MONGO_NODE1_PORT}" 'db.getSiblingDB("admin").getUser(process.env.MONGO_ROOT_USERNAME) ? "yes" : "no"' 2>/dev/null || true)"
  if ! grep -qx 'yes' <<<"${user_exists}"; then
    printf 'No se pudo autenticar con el usuario administrador recién creado\n' >&2
    return 1
  fi
}

print_summary() {
  printf '\nCluster listo.\n'
  printf 'Replica set: %s\n' "${MONGO_REPLICA_SET_NAME}"
  printf 'Nodos: %s:%s, %s:%s, %s:%s\n' \
    "${MONGO_NODE1_HOST}" "${MONGO_NODE1_PORT}" \
    "${MONGO_NODE2_HOST}" "${MONGO_NODE2_PORT}" \
    "${MONGO_NODE3_HOST}" "${MONGO_NODE3_PORT}"
}

require_command docker
require_command openssl

if ! docker compose version >/dev/null 2>&1; then
  printf 'docker compose no está disponible\n' >&2
  exit 1
fi

ensure_keyfile
start_nodes
wait_for_all_nodes
initiate_replicaset
wait_for_primary
ensure_admin_user
print_summary
