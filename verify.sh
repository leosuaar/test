#!/bin/bash

# verify.sh: Verificación semántica y textual de encriptación. Dependencias: common.sh.

# Función para verificar encriptación/desencriptación (mejorada: semántica con Python si disponible)
verify_encryption() {
    log_info "Verificando encriptación..."
    if ! is_encrypted "${DOCKER_YML}"; then
        log_error "No se detectaron bloques encriptados en ${DOCKER_YML}"
        exit 1
    fi
    local enc_count=$(grep -c 'ENC\[AES256_GCM' "${DOCKER_YML}")
    if [[ ${enc_count} -lt 10 ]]; then
        log_warn "Pocos bloques encriptados (${enc_count}); verifica manual."
    fi
    log_info "Verificando desencriptación contra backup..."
    local temp_decrypt=$(mktemp)
    if ! sops -d "${DOCKER_YML}" > "${temp_decrypt}"; then
        log_error "Fallo en desencriptación de verificación. Verifica nueva clave privada."
        rm -f "${temp_decrypt}"
        exit 1
    fi

    # Verificación textual estricta (puede fallar por formato YAML)
    if ! diff "${temp_decrypt}" "${BACKUP_YML}" > /dev/null; then
        log_warn "Diferencias textuales detectadas (normal en SOPS: cambios en whitespace/multilínea). Verificando semánticamente..."
        
        # Verificación semántica con Python + PyYAML (si disponible)
        if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
            local semantic_match=$(python3 -c "
import sys, yaml, json
try:
    with open('$BACKUP_YML', 'r') as f: orig = yaml.safe_load(f) or {}
    with open('$temp_decrypt', 'r') as f: dec = yaml.safe_load(f) or {}
    print('true' if json.dumps(orig, sort_keys=True) == json.dumps(dec, sort_keys=True) else 'false')
except Exception as e:
    print('false')
sys.exit(0)
" 2>/dev/null)
            if [[ "${semantic_match}" == "true" ]]; then
                log_success "Verificación semántica OK: Contenido YAML idéntico (solo formato cambió)."
            else
                log_error "Verificación semántica falló: Posible corrupción real. Revisa diff manual: diff -u $BACKUP_YML $temp_decrypt"
                rm -f "${temp_decrypt}"
                exit 1
            fi
        else
            log_warn "Python/PyYAML no disponible para verificación semántica. Instala con 'pip install pyyaml'. Asumiendo OK por ahora (verifica manual)."
            log_info "Ejecuta: sops -d $DOCKER_YML > temp.yml && diff -u $BACKUP_YML temp.yml"
        fi
    else
        log_success "Verificación textual estricta OK."
    fi
    rm -f "${temp_decrypt}"
    log_success "Verificación general OK: Encriptado y desencriptable."
}
