#!/bin/bash

# prereqs.sh: Verifica prerrequisitos y genera claves iniciales. Dependencias: common.sh.

# Función para verificar prerrequisitos (sin rotación)
check_prereqs() {
    log_info "Verificando prerrequisitos..."
    if ! command -v sops &> /dev/null; then
        log_error "sops no encontrado. Instala con: curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 && sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops && sudo chmod +x /usr/local/bin/sops"
        exit 1
    fi
    if ! command -v age &> /dev/null; then
        log_error "age no encontrado. Instala con: sudo apt install age"
        exit 1
    fi
    
    # Check para Docker Compose v1 o v2
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        log_success "Docker Compose v1 detectado."
    elif docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        log_success "Docker Compose v2 (plugin) detectado."
    else
        log_error "Docker Compose no encontrado (ni v1 ni v2). Para v2: sudo apt install docker-compose-plugin"
        exit 1
    fi
    export COMPOSE_CMD  # Exportar para usar en alias
    
    if [[ ! -f "${DOCKER_YML}" ]]; then
        log_error "docker-compose.yml no encontrado en ${SCRIPT_DIR}"
        exit 1
    fi
    
    # Verificar que hay al menos alguna clave (current o old)
    if [[ ! -f "${PRIVATE_KEYS_FILE}" ]] && [[ ! -f "${SOPS_DIR}/old_keys_"* ]]; then
        log_warn "No hay claves (ni current ni old). Generando iniciales..."
        generate_initial_keys
    fi
    
    log_success "Prerrequisitos OK."
}

# Función para generar claves iniciales (solo si no existen)
generate_initial_keys() {
    log_info "Generando claves iniciales age..."
    if [[ ! -d "${SOPS_DIR}" ]]; then
        mkdir -p "${SOPS_DIR}"
        log_success "Directorio ${SOPS_DIR} creado."
    fi
    age-keygen -o "${PRIVATE_KEY_FILE}"
    chmod 600 "${PRIVATE_KEY_FILE}"
    age-keygen -y "${PRIVATE_KEY_FILE}" > "${PUBLIC_KEY_FILE}"
    grep '^AGE-SECRET-KEY' "${PRIVATE_KEY_FILE}" > "${PRIVATE_KEYS_FILE}"
    chmod 600 "${PRIVATE_KEYS_FILE}"
    log_success "Claves iniciales generadas."
}
