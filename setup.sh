#!/bin/bash

# setup.sh: Configuración de aliases y SOPS config. Dependencias: common.sh, prereqs.sh (para COMPOSE_CMD).

# Función para setup de alias en .bashrc
setup_aliases() {
    log_info "Configurando alias en ${BASHRC}..."
    local alias_def="alias dc=\"sops -d docker-compose.yml | ${COMPOSE_CMD} -f -\""
    if ! grep -q "${alias_def}" "${BASHRC}"; then
        echo "" >> "${BASHRC}"
        echo "# Alias para docker-compose con sops (agregado por encriptadorYAML.sh)" >> "${BASHRC}"
        echo "${alias_def}" >> "${BASHRC}"
        log_success "Alias 'dc' agregado. Recarga con: source ~/.bashrc"
    else
        log_warn "Alias ya existe."
    fi
    log_info "Para up: dc up -d"
    log_info "Para down: dc down"
}
