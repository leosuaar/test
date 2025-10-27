#!/bin/bash

# keys.sh: Rotación de claves y helpers para decrypt con keys. Dependencias: common.sh.

# Función: Rotar claves age (genera nuevas y backup antiguas)
rotate_keys() {
    local timestamp="$1"
    log_info "Rotando claves age para nueva encriptación..."
    
    # Si usó old key, backup esa también como "used_old"
    if [[ "${USED_OLD_KEY}" == true ]]; then
        local used_old_file="${SOPS_DIR}/used_old_key_${timestamp}.txt"
        cp "${PRIVATE_KEYS_FILE}" "${used_old_file}"  # Asumiendo que set_working_key copió la working a current
        log_info "Clave old usada respaldada en ${used_old_file}"
    fi
    
    # Backup de claves actuales (que podrían ser la old working o previous current)
    if [[ -f "${PRIVATE_KEY_FILE}" ]]; then
        mv "${PRIVATE_KEY_FILE}" "${SOPS_DIR}/old_key_${timestamp}.key"
        log_info "Clave privada actual respaldada en old_key_${timestamp}.key"
    fi
    if [[ -f "${PUBLIC_KEY_FILE}" ]]; then
        mv "${PUBLIC_KEY_FILE}" "${SOPS_DIR}/old_pub_${timestamp}.pub"
        log_info "Clave pública actual respaldada en old_pub_${timestamp}.pub"
    fi
    if [[ -f "${PRIVATE_KEYS_FILE}" ]]; then
        mv "${PRIVATE_KEYS_FILE}" "${SOPS_DIR}/old_keys_${timestamp}.txt"
        log_info "Keys.txt actual respaldada en old_keys_${timestamp}.txt"
    fi
    
    # Generar nuevas claves
    log_info "Generando nuevas claves age..."
    age-keygen -o "${PRIVATE_KEY_FILE}"
    chmod 600 "${PRIVATE_KEY_FILE}"
    age-keygen -y "${PRIVATE_KEY_FILE}" > "${PUBLIC_KEY_FILE}"
    grep '^AGE-SECRET-KEY' "${PRIVATE_KEY_FILE}" > "${PRIVATE_KEYS_FILE}"
    chmod 600 "${PRIVATE_KEYS_FILE}"
    
    log_success "Nuevas claves generadas y configuradas."
    log_warn "¡Guarda los backups de claves en un lugar seguro!"
}

# Función para intentar decrypt con una clave privada específica
try_decrypt_with_key() {
    local key_file="$1"
    local output_file="$2"
    local key_content=$(cat "${key_file}" | grep '^AGE-SECRET-KEY' | head -1)
    if [[ -z "${key_content}" ]]; then
        return 1
    fi
    if sops -d --age "${key_content}" "${DOCKER_YML}" > "${output_file}" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Función para setear la clave working como current (si old funcionó)
set_working_key() {
    local working_key_file="$1"
    local key_content=$(cat "${working_key_file}" | grep '^AGE-SECRET-KEY' | head -1)
    echo "${key_content}" > "${PRIVATE_KEYS_FILE}"
    chmod 600 "${PRIVATE_KEYS_FILE}"
    log_info "Clave working seteada como current para esta sesión."
    USED_OLD_KEY=true
}
