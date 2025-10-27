#!/bin/bash

# main.sh: Entry point principal. Orquesta el flujo: carga módulos y ejecuta secuencia.
# Uso: ./main.sh
# Dependencias: Todos los .sh en el mismo dir.

set -euo pipefail  # Modo estricto: exit on error, undefined vars, pipe fail.

# Cargar módulos en orden (agrega nuevos sources aquí para extender)
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/prereqs.sh"
source "${SCRIPT_DIR}/keys.sh"
source "${SCRIPT_DIR}/sops_ops.sh"
source "${SCRIPT_DIR}/verify.sh"
source "${SCRIPT_DIR}/setup.sh"
source "${SCRIPT_DIR}/cleanup.sh"

# Función principal
main() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    log_info "=== Iniciando encriptación/rotación de docker-compose.yml ==="
    
    check_prereqs  # Prerreqs y keys iniciales si no hay
    
    # Backup encriptado si ya está encriptado (ANTES de decrypt)
    if is_encrypted "${DOCKER_YML}"; then
        cp "${DOCKER_YML}" "${ENCRYPTED_BACKUP}.${timestamp}"
        log_info "Backup encriptado previo creado: ${ENCRYPTED_BACKUP}.${timestamp}"
    fi
    
    decrypt_if_needed  # Desencripta con current o old
    backup_file  # Backup del plaintext post-decrypt
    
    if [[ "${WAS_ENCRYPTED}" == true ]]; then
        log_info "Rotación requerida (era encriptado)."
    else
        log_info "Encriptación inicial."
    fi
    
    rotate_keys "${timestamp}"  # Rota a nuevas
    create_sops_config
    encrypt_yml
    verify_encryption  # Ahora maneja el issue de formato
    setup_aliases
    log_success "=== Proceso completado. Archivo encriptado con nuevas claves. Usa 'dc up -d' para iniciar. ==="
    echo -e "${GREEN}Ejemplos:${NC}"
    echo "  # Iniciar servicios: dc up -d"
    echo "  # Detener: dc down"
    echo "  # Logs: dc logs rclone_ulozVault"  # Ajusta si tu servicio es diferente
    echo "  # Recargar alias: source ~/.bashrc"
    echo -e "${YELLOW}Verifica: cat docker-compose.yml | head -20 ${NC}(debe mostrar muchos ENC[...])"
    log_info "Backup encriptado previo: ${ENCRYPTED_BACKUP}.${timestamp} (si aplica)"
    if [[ "${USED_OLD_KEY}" == true ]]; then
        log_warn "Usó clave old para decrypt. Claves rotadas y respaldadas en ~/.config/sops/age/old_*_${timestamp}.*"
    fi

    # Recargar .bashrc si es interactivo
    if [ -t 0 ]; then
        source ~/.bashrc
        log_success "Alias 'dc' activado. ¡Prueba: dc up -d!"
    fi

    # Llamar a las funciones de limpieza al final (solo interactiva)
    cleanup_old_files
    cleanup_final_files
    cleanup_total_desinstalacion  # Nueva fase destructiva opcional
    log_success "=== Script finalizado exitosamente. Puedes usar 'dc up -d' ahora. ==="
}

# Ejecutar si no es sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
