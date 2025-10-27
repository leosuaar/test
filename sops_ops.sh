#!/bin/bash

# sops_ops.sh: Decrypt, encrypt y config de SOPS. Dependencias: common.sh, keys.sh.

# Función para desencriptar temporalmente (si ya encriptado), con fallback a old keys
decrypt_if_needed() {
    if is_encrypted "${DOCKER_YML}"; then
        WAS_ENCRYPTED=true
        local temp_plain=$(mktemp)
        log_info "Archivo ya encriptado detectado. Intentando desencriptar con claves actuales..."
        
        # Intento 1: Con current keys.txt
        if try_decrypt_with_key "${PRIVATE_KEYS_FILE}" "${temp_plain}"; then
            log_success "Desencriptado con clave actual exitoso."
        else
            log_warn "Fallo con clave actual. Probando con claves old..."
            local found_key=false
            for old_key_file in "${SOPS_DIR}/old_keys_"*.txt; do
                if [[ -f "${old_key_file}" ]]; then
                    log_info "Probando con ${old_key_file}..."
                    if try_decrypt_with_key "${old_key_file}" "${temp_plain}"; then
                        log_success "¡Desencriptado exitoso con old key: ${old_key_file}!"
                        set_working_key "${old_key_file}"
                        found_key=true
                        break
                    fi
                fi
            done
            if [[ "${found_key}" != true ]]; then
                log_error "Fallo en todas las claves (current y old). Verifica backups manualmente o restaura plaintext desde backup."
                rm -f "${temp_plain}"
                exit 1
            fi
        fi
        
        mv "${temp_plain}" "${DOCKER_YML}"
        log_success "Desencriptado temporal completado. Archivo ahora es plaintext."
    else
        log_info "Archivo plaintext detectado. Procediendo a encriptación inicial."
    fi
}

# Función para crear .sops.yaml (simplificada)
create_sops_config() {
    PUBLIC_KEY=$(cat "${PUBLIC_KEY_FILE}" | tr -d '\n ')
    log_info "Creando config sops básica: ${SOPS_CONFIG}"
    cat > "${SOPS_CONFIG}" << EOF
creation_rules:
  - path_regex: \.(yml|yaml)\$
    age: '${PUBLIC_KEY}'
EOF
    log_success "Config sops creada."
}

# Función para encriptar
encrypt_yml() {
    PUBLIC_KEY=$(cat "${PUBLIC_KEY_FILE}" | tr -d '\n ')
    log_info "Encriptando ${DOCKER_YML} con nuevas claves (full encryption)..."
    sops -e --age "${PUBLIC_KEY}" "${DOCKER_YML}" > "${ENCRYPTED_YML}" || {
        log_error "Fallo en encriptación. Verifica clave pública: ${PUBLIC_KEY}"
        exit 1
    }
    mv "${ENCRYPTED_YML}" "${DOCKER_YML}"
    log_success "Archivo re-encriptado con nuevas claves: ${DOCKER_YML}"
}
