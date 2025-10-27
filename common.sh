#!/bin/bash

# common.sh: Variables globales, colores y logging. Dependencias: Ninguna.

# Colores para logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_YML="${SCRIPT_DIR}/docker-compose.yml"
BACKUP_YML="${SCRIPT_DIR}/docker-compose.yml.backup"
ENCRYPTED_BACKUP="${SCRIPT_DIR}/docker-compose.encrypted.backup"
ENCRYPTED_YML="${SCRIPT_DIR}/docker-compose.yml.enc"  # Temporal para encriptación
SOPS_CONFIG="${SCRIPT_DIR}/.sops.yaml"
BASHRC="${HOME}/.bashrc"
PUBLIC_KEY_FILE="${HOME}/.config/sops/age.pub"
PRIVATE_KEYS_FILE="${HOME}/.config/sops/age/keys.txt"
PRIVATE_KEY_FILE="${HOME}/.config/sops/age.key"
SOPS_DIR="${HOME}/.config/sops/age"
SOPS_ROOT="${HOME}/.config/sops"
WAS_ENCRYPTED=false  # Flag global para saber si era encriptado
USED_OLD_KEY=false  # Flag para saber si usó old key
COMPOSE_CMD=""  # Se setea en prereqs.sh

# Función de logging
log() {
    local level="$1"
    shift
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${level}] $@"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@" >&2; }
log_error() { log "ERROR" "$@" >&2; }
log_success() { log "SUCCESS" "$@"; }

# Helper: Verificar si el archivo está encriptado
is_encrypted() {
    local file="$1"
    grep -q 'ENC\[AES256_GCM' "${file}" 2>/dev/null
}

# Helper: Backup del plaintext
backup_file() {
    log_info "Creando backup del plaintext: ${BACKUP_YML}"
    cp "${DOCKER_YML}" "${BACKUP_YML}" || {
        log_error "Fallo en backup"
        exit 1
    }
    log_success "Backup plaintext creado."
}
