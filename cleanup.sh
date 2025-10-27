#!/bin/bash

# cleanup.sh: Todas las funciones de limpieza. Dependencias: common.sh, prereqs.sh (para COMPOSE_CMD).

# Función para limpieza de archivos old en ~/.config/sops/age/ (solo si interactivo)
cleanup_old_files() {
    log_info "=== OPCIÓN DE LIMPIEZA ==="
    log_info "Buscando archivos old en ${SOPS_DIR}..."
    local old_files=($(find "${SOPS_DIR}" -maxdepth 1 -name 'old_*' -type f 2>/dev/null || true))
    local count=${#old_files[@]}
    log_info "Detectados ${count} archivos old."

    if [[ ${count} -eq 0 ]]; then
        log_info "No hay archivos old para limpiar."
        return 0
    fi

    echo -e "\n${YELLOW}Se detectaron ${count} archivos backups de claves anteriores:${NC}"
    for file in "${old_files[@]}"; do
        echo -e "${YELLOW}  - $(basename "${file}")${NC}"
    done

    echo -e "\n${YELLOW}Si ya no planeas desencriptar con claves old (o si tienes backups externos seguros), puedes borrarlos para ahorrar espacio.${NC}"
    echo -e "${RED}¡ADVERTENCIA: Una vez borrados, solo podrás desencriptar con la clave actual! Si necesitas claves old para archivos antiguos, guárdalos en otro lugar primero.${NC}"

    # Solo proceder si es interactivo (TTY)
    if [ -t 0 ]; then
        read -p "¿Quieres borrar TODOS los archivos old_* detectados? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            for file in "${old_files[@]}"; do
                rm -f "${file}"
                log_info "Borrado: $(basename "${file}")"
            done
            log_success "Limpieza completada. ${count} archivos old borrados."
        else
            log_info "Limpieza cancelada. Los archivos old se mantienen."
        fi
    else
        log_warn "Ejecución no interactiva detectada. Saltando limpieza de archivos old para evitar errores. Ejecuta en terminal para opciones interactivas."
        return 0
    fi

    echo -e "\n${YELLOW}Si quieres borrar archivos específicos, hazlo manualmente con: rm <archivo>${NC}"
    echo -e "${GREEN}Estado actual de ${SOPS_DIR}: ${NC}"
    ls -la "${SOPS_DIR}"
}

# Función para limpieza final de archivos no esenciales (solo si interactivo, después de no encriptar más)
cleanup_final_files() {
    log_info "=== LIMPIEZA FINAL: ARCHIVOS NO ESENCIALES (OPCIONAL) ==="
    log_info "Buscando archivos no esenciales en ${SCRIPT_DIR} y ${SOPS_ROOT}..."
    local safe_files=()
    local safe_dirs=()
    local count=0

    # Recopilar archivos y directorios seguros para borrar (silenciosamente)
    if [[ -f "${PUBLIC_KEY_FILE}" ]]; then
        safe_files+=("${PUBLIC_KEY_FILE}")
        count=$((count + 1))
    fi

    if [[ -d "${SOPS_DIR}" ]] && [[ -z "$(ls -A "${SOPS_DIR}")" ]]; then
        safe_dirs+=("${SOPS_DIR}")
    fi

    if [[ -f "${BACKUP_YML}" ]]; then
        safe_files+=("${BACKUP_YML}")
        count=$((count + 1))
    fi

    # Backups encriptados (usando find para lista rápida)
    local enc_backups=($(find "${SCRIPT_DIR}" -maxdepth 1 -name 'docker-compose.encrypted.backup.*' -type f 2>/dev/null || true))
    local num_enc=${#enc_backups[@]}
    count=$((count + num_enc))
    safe_files+=("${enc_backups[@]}")

    if [[ -f "${SOPS_CONFIG}" ]]; then
        safe_files+=("${SOPS_CONFIG}")
        count=$((count + 1))
    fi

    log_info "Detectados ${count} elementos no esenciales."

    if [[ ${count} -eq 0 && ${#safe_dirs[@]} -eq 0 ]]; then
        log_info "No hay archivos/directorios no esenciales para limpiar."
        log_success "Limpieza final completada: No se encontraron elementos para borrar."
        return 0
    fi

    # Mostrar lista completa solo ahora
    echo -e "\n${YELLOW}Se detectaron ${count} archivos/directorios seguros para borrar si no planeas encriptar/desencriptar más (el alias 'dc' seguirá funcionando con age.key intacto).${NC}"
    if [[ -f "${PUBLIC_KEY_FILE}" ]]; then
        echo -e "${YELLOW}  - ${PUBLIC_KEY_FILE##*/} (clave pública, regenerable si necesitas encriptar de nuevo)${NC}"
    fi
    if [[ -d "${SOPS_DIR}" ]] && [[ -z "$(ls -A "${SOPS_DIR}")" ]]; then
        echo -e "${YELLOW}  - ${SOPS_DIR##*/}/ (directorio vacío de backups old)${NC}"
    fi
    if [[ -f "${BACKUP_YML}" ]]; then
        echo -e "${YELLOW}  - ${BACKUP_YML##*/} (backup plaintext, no necesario si no editarás)${NC}"
    fi
    if [[ ${num_enc} -gt 0 ]]; then
        echo -e "${YELLOW}  - ${num_enc} backups encriptados anteriores (ej. docker-compose.encrypted.backup.*)${NC}"
    fi
    if [[ -f "${SOPS_CONFIG}" ]]; then
        echo -e "${YELLOW}  - ${SOPS_CONFIG##*/} (config SOPS, no necesario si no encriptarás más)${NC}"
    fi

    echo -e "${RED}¡ADVERTENCIA: NO se toca age.key (clave privada esencial para dc up/down) ni docker-compose.yml (encriptado principal). Si respondes 's', se borran todos los listados.${NC}"
    echo -e "${GREEN}Archivos esenciales que NO se tocan:${NC}"
    echo "  - age.key (clave privada para desencriptar)"
    echo "  - docker-compose.yml (archivo encriptado principal)"
    echo "  - keys.txt (clave actual)"

    # Solo proceder si es interactivo (TTY)
    if [ -t 0 ]; then
        read -p "¿Quieres borrar TODOS los archivos/directorios no esenciales listados? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            # Borrar archivos
            for file in "${safe_files[@]}"; do
                rm -f "${file}"
                log_info "Borrado: ${file##*/}"
            done
            # Borrar directorios vacíos
            for dir in "${safe_dirs[@]}"; do
                rmdir "${dir}" 2>/dev/null && log_info "Directorio borrado: ${dir##*/}"
            done
            log_success "Limpieza final completada. ${count} elementos no esenciales borrados."
        else
            log_info "Limpieza final cancelada. Los archivos no esenciales se mantienen."
            log_success "Limpieza final completada: No se borró nada (cancelado por usuario)."
        fi
    else
        log_warn "Ejecución no interactiva detectada. Saltando limpieza final para evitar errores. Ejecuta en terminal para opciones interactivas."
        log_success "Limpieza final completada: Saltada por modo no interactivo."
        return 0
    fi

    echo -e "\n${YELLOW}Verifica el estado:${NC}"
    echo -e "${GREEN}En ${SCRIPT_DIR}: ${NC}"
    ls -la "${SCRIPT_DIR}" | grep -E "(docker-compose|backup|\.sops)" || echo "No hay más backups."
    echo -e "${GREEN}En ${SOPS_ROOT}: ${NC}"
    ls -la "${SOPS_ROOT}"
    log_success "Limpieza final completada: Verificación de estado OK."
}

# Nueva función para desinstalación total (borrar script, sops dir, claves, y desinstalar SOPS) - OPCIONAL y destructiva
cleanup_total_desinstalacion() {
    log_info "=== DESINSTALACIÓN TOTAL: LIMPIEZA COMPLETA (OPCIONAL Y DESTRUCTIVA) ==="
    log_info "Si ya no necesitas encriptar/desencriptar más (servicios Docker corriendo sin cambios), esta opción borra TODO lo relacionado."
    
    # Mostrar ubicación de clave privada
    echo -e "\n${YELLOW}Ubicación de la clave privada actual:${NC}"
    if [[ -f "${PRIVATE_KEY_FILE}" ]]; then
        echo -e "${GREEN}  - ${PRIVATE_KEY_FILE} (clave privada maestra para desencriptar)${NC}"
    else
        log_warn "No se encontró la clave privada en ${PRIVATE_KEY_FILE}. Verifica manualmente."
    fi
    echo -e "${YELLOW}También se borrará:${NC}"
    echo "  - Este script: ${SCRIPT_DIR}/main.sh (y otros .sh)"
    echo "  - Todo el directorio: ${SOPS_ROOT} (incluyendo claves privadas, keys.txt, etc.)"
    echo "  - Alias 'dc' de ~/.bashrc (para evitar errores)"
    echo "  - SOPS se desinstalará (asumiendo apt; ajusta si usas otro gestor)"
    echo "  - Age se desinstalará (si instalado via apt)"

    echo -e "\n${RED}¡ADVERTENCIA MÁXIMA: Esto es IRREVERSIBLE!${NC}"
    echo -e "${RED}  - Borrarás claves privadas: NO podrás desencriptar docker-compose.yml nunca más.${NC}"
    echo -e "${RED}  - Alias 'dc' fallará sin SOPS (usa 'docker compose up -d' directamente).${NC}"
    echo -e "${RED}  - Si editas docker-compose.yml en el futuro, tendrás que re-encriptar manualmente.${NC}"
    echo -e "${GREEN}¡Asegúrate de tener backups de claves si las necesitas!${NC}"

    # Solo proceder si es interactivo (TTY)
    if [ -t 0 ]; then
        read -p "¿Quieres proceder con la desinstalación total? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            # Borrar los scripts .sh (excepto este, pero como es main, se borra al final)
            for script in "${SCRIPT_DIR}"/*.sh; do
                rm -f "${script}"
                log_info "Script borrado: $(basename "${script}")"
            done

            # Borrar todo el directorio sops (incluyendo claves)
            rm -rf "${SOPS_ROOT}"
            log_info "Directorio SOPS borrado completamente: ${SOPS_ROOT} (incluyendo claves privadas)"

            # Remover alias de .bashrc
            if grep -q "# Alias para docker-compose con sops" "${BASHRC}"; then
                sed -i '/# Alias para docker-compose con sops/,/alias dc=/d' "${BASHRC}"
                log_info "Alias 'dc' removido de ${BASHRC}. Recarga con: source ~/.bashrc"
            else
                log_warn "Alias 'dc' no encontrado en ${BASHRC}. Saltando remoción."
            fi

            # Desinstalar SOPS y age (asumiendo apt; ajusta si es brew, etc.)
            local sops_removed=false
            local age_removed=false
            if command -v apt &> /dev/null; then
                sudo apt remove -y sops >/dev/null 2>&1 && sops_removed=true || log_warn "SOPS no encontrado en apt (probablemente instalado manualmente)."
                sudo apt remove -y age >/dev/null 2>&1 && age_removed=true || log_warn "Fallo en desinstalación de age (ejecuta manual: sudo apt remove age)"

                # Siempre intentar remover SOPS manualmente de /usr/local/bin (incluso si apt falló)
                if sudo rm -f /usr/local/bin/sops 2>/dev/null; then
                    log_success "SOPS removido manualmente de /usr/local/bin/sops."
                    sops_removed=true
                elif [[ ! -f /usr/local/bin/sops ]]; then
                    log_info "SOPS ya no existe en /usr/local/bin (ya estaba removido o no instalado)."
                    sops_removed=true
                else
                    log_warn "No se pudo remover /usr/local/bin/sops manualmente. Verifica permisos."
                fi

                if [[ "${sops_removed}" == true && "${age_removed}" == true ]]; then
                    log_success "SOPS y age desinstalados exitosamente."
                elif [[ "${sops_removed}" == true ]]; then
                    log_success "SOPS desinstalado (age podría requerir remoción manual)."
                elif [[ "${age_removed}" == true ]]; then
                    log_success "Age desinstalado (SOPS podría requerir remoción manual)."
                else
                    log_warn "Ninguno de SOPS o age se desinstaló automáticamente. Verifica manualmente."
                fi
            else
                log_warn "Gestor de paquetes no detectado (apt). Desinstala SOPS y age manualmente."
                # Intento manual de rm si no apt
                if sudo rm -f /usr/local/bin/sops 2>/dev/null; then
                    log_success "SOPS removido manualmente de /usr/local/bin/sops."
                else
                    log_warn "No se pudo remover /usr/local/bin/sops manualmente."
                fi
            fi

            log_success "=== Desinstalación total completada. Servicios Docker siguen funcionando sin cambios. ==="
            echo -e "${GREEN}¡Felicidades! Todo limpio. Usa 'docker compose up -d' para futuros comandos.${NC}"
        else
            log_info "Desinstalación total cancelada. Todo se mantiene intacto."
            log_success "Desinstalación total completada: No se hizo nada (cancelado por usuario)."
        fi
    else
        log_warn "Ejecución no interactiva detectada. Saltando desinstalación total para evitar destrucción accidental."
        log_success "Desinstalación total completada: Saltada por modo no interactivo."
        return 0
    fi
}
