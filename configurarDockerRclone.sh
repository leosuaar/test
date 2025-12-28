#!/bin/bash

# Script de setup v2: Crea usuario tux (si no existe), asigna sudo, crea directorio docker, y configura rclone.conf y docker-compose.yml COMO tux
# Uso: ./setup-tux-configs.sh  (ejecutar como root; te pedirá contraseña ANTES de crear tux si no existe, y luego configs interactivas)
# Al final, regresa a root.
# Verificación de errores: Se agregan chequeos de exit code después de comandos críticos. Si falla, muestra error y sale.
# Validación de entrada: Verifica que se ejecute como root, contraseña mínima de 8 chars, configs no vacíos.
# Ajuste: Si el usuario 'tux' ya existe, omite la creación y configuración de contraseña/grupo sudo.
# Nota: Siempre pide configs para permitir sobrescritura/actualización. La ejecución de docker compose up -d se mueve al final como último paso.
# FIX 2025-11-02 v2: Pre-clean Docker down + chown/chmod específico en jellyfin/config; limpia .partials; verificación final de ownership en subdirs.

set -u  # Trata variables no definidas como error

# Función para verificar errores
check_error() {
    if [ $? -ne 0 ]; then
        echo "ERROR: El comando anterior falló. Abortando script."
        exit 1
    fi
}

# Función para validar contraseña (mínimo 8 caracteres)
validate_password() {
    local pass="$1"
    if [ ${#pass} -lt 8 ]; then
        echo "ERROR: La contraseña debe tener al menos 8 caracteres."
        return 1
    fi
    return 0
}

# Función para validar y/n input
validate_yn() {
    local input="$1"
    if [[ ! "$input" =~ ^[YyNn]$ ]]; then
        echo "ERROR: Entrada inválida. Debe ser 'y' o 'n'."
        return 1
    fi
    return 0
}

# ========================================
# VALIDACIÓN INICIAL: Verificar que se ejecute como root
# ========================================
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Este script debe ejecutarse como root (use sudo)."
    exit 1
fi

# ========================================
# PASO INICIAL: Verificar si usuario 'tux' ya existe (aseguramos que exista antes de proceder)
# ========================================
TUX_EXISTS=false
if id "tux" &>/dev/null; then
    echo "Usuario 'tux' ya existe. Procediendo con configuración."
    TUX_EXISTS=true
else
    # Solicitar contraseña ANTES de crear el usuario
    echo "El usuario 'tux' no existe. Se creará ahora para evitar problemas en pasos posteriores."
    echo "Ingrese la contraseña para 'tux' (mínimo 8 caracteres):"
    read -s PASSWORD
    echo  # Nueva línea para continuar limpio

    if [ -z "$PASSWORD" ]; then
        echo "ERROR: La contraseña no puede estar vacía."
        exit 1
    fi

    if ! validate_password "$PASSWORD"; then
        exit 1
    fi

    echo "Creando usuario 'tux' de forma no interactiva..."
    useradd -m -s /bin/bash tux
    check_error

    echo "Seteando contraseña para 'tux'..."
    echo "tux:$PASSWORD" | chpasswd
    check_error
fi

# Agregar a grupo sudo solo si no está ya
if ! groups tux | grep -q sudo; then
    echo "Agregando 'tux' al grupo sudo..."
    usermod -aG sudo tux
    check_error
else
    echo "'tux' ya está en el grupo sudo. Omitiendo."
fi

# ========================================
# PRE-FIX: Limpieza agresiva de /home/tux/docker si existe
# ========================================
DOCKER_DIR="/home/tux/docker"
JELLYFIN_CONFIG="$DOCKER_DIR/jellyfin/config"

if [ -d "$DOCKER_DIR" ]; then
    echo "Detectado $DOCKER_DIR. Iniciando pre-clean..."
    
    # Detener Docker si compose.yml existe (evita locks)
    if [ -f "$DOCKER_DIR/docker-compose.yml" ]; then
        echo "Deteniendo servicios Docker temporalmente..."
        su - tux -c "cd ~/docker && docker compose down || true"
        check_error
    fi
    
    # Forzar ownership full
    echo "Forzando chown -R tux:tux en $DOCKER_DIR..."
    chown -R tux:tux "$DOCKER_DIR"
    check_error
    
    # Permisos específicos para jellyfin/config (más granulares)
    if [ -d "$JELLYFIN_CONFIG" ]; then
        echo "Aplicando permisos granulares a $JELLYFIN_CONFIG..."
        find "$JELLYFIN_CONFIG" -type d -exec chmod 755 {} \;
        check_error
        find "$JELLYFIN_CONFIG" -type f -exec chmod 644 {} \;
        check_error
        # Limpia partials viejos de rclone
        find "$JELLYFIN_CONFIG" -name "*.partial" -delete || true
        echo "Partials limpiados."
    fi
    
    echo "Pre-clean completado. Ownership: $(ls -la "$DOCKER_DIR" | head -1)"
else
    echo "/home/tux/docker no existe aún. Se creará en el siguiente paso."
fi

# ========================================
# FIX: Forzar ownership de /home/tux/docker como root (antes de su-tux) para subdirs existentes
# ========================================
if [ -d "$DOCKER_DIR" ]; then
    echo "Detectado /home/tux/docker existente. Forzando ownership a tux:tux para evitar errores de permisos en subdirs (ej. jellyfin/config)..."
    chown -R tux:tux "$DOCKER_DIR"
    check_error
    echo "Ownership corregido. Verificación: $(ls -la "$DOCKER_DIR" | head -1)"
fi

# ========================================
# GRUPO 7: Instalar sops y age (para encriptación de YAML con sops)
# ========================================
# Este grupo instala sops (binario directo) y age (paquete APT) si no existen.
# sops: Descarga la versión estable desde GitHub; mv a /usr/local/bin para PATH global.
# age: Disponible en repos de Ubuntu; asegura encriptación age para sops.
echo "Verificando instalación de sops y age..."
if ! command -v sops >/dev/null 2>&1; then
    echo "Instalando sops..."
    curl -LO https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
    check_error
    mv sops-v3.11.0.linux.amd64 /usr/local/bin/sops
    check_error
    chmod +x /usr/local/bin/sops
    check_error
else
    echo "sops ya instalado. Omitiendo."
fi
if ! command -v age >/dev/null 2>&1; then
    echo "Instalando age..."
    apt-get update
    check_error
    apt-get install -y age
    check_error
else
    echo "age ya instalado. Omitiendo."
fi

# ========================================
# CONFIGURACIÓN DE SUDO NOPASSWD PARA TUX (temporal para prompts interactivos en su -c)
# ========================================
echo "Configurando sudo sin contraseña para 'tux' (temporal para setup)..."
echo "tux ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/tux
check_error
chmod 0440 /etc/sudoers.d/tux
check_error
echo "Configuración de sudoers aplicada."

# ========================================
# PASO PRINCIPAL: Configurar directorio, archivos como 'tux' (sin ejecutar compose aún)
# ========================================
echo "Ejecutando configuración de directorio y archivos como usuario 'tux'..."
su - tux -c '
set -u  # Trata variables no definidas como error

# Función para verificar errores (dentro de su)
check_error() {
    if [ $? -ne 0 ]; then
        echo "ERROR: El comando anterior falló. Abortando script."
        exit 1
    fi
}

# ========================================
# GRUPO 1: Crear directorio docker en /home/tux/ (como tux) y asignar permisos totales
# ========================================
echo "Creando directorio /home/tux/docker si no existe..."
mkdir -p ~/docker
check_error
echo "Asignando permisos totales (755 recursivo) a /home/tux/docker y subdirectorios para usuario tux (usando sudo para forzar)..."
sudo chmod -R 755 ~/docker
check_error

# ========================================
# GRUPO 2: Configurar archivo de rclone.conf (como tux) - SIEMPRE PIDE PARA ACTUALIZAR
# ========================================
# Este grupo solicita interactivamente el texto completo del archivo de configuración de rclone.
# Usa cat para leer multi-línea: pega el contenido completo y termina con Ctrl+D (EOF) en una línea nueva.
# Luego, crea el directorio ~/.config/rclone si no existe y guarda el config en rclone.conf.
echo "Pegue el texto completo del archivo de configuración de rclone (copie y pegue todo el contenido). Esto sobrescribirá el existente."
echo "Cuando termine, presione Enter en una línea nueva y luego Ctrl+D (EOF) para continuar."
RCLONE_CONFIG=$(cat)
if [ -z "$RCLONE_CONFIG" ]; then
    echo "ERROR: El archivo de configuración de rclone está vacío."
    exit 1
fi
mkdir -p ~/.config/rclone
check_error
echo "$RCLONE_CONFIG" > ~/.config/rclone/rclone.conf
check_error
echo "Archivo de configuración de rclone actualizado en ~/.config/rclone/rclone.conf"

# ========================================
# GRUPO 3: Configurar archivo de docker-compose.yml (como tux) - SIEMPRE PIDE PARA ACTUALIZAR
# ========================================
# Este grupo solicita interactivamente el texto completo del archivo de configuración de docker-compose.
# Usa cat para leer multi-línea: pega el contenido completo y termina con Ctrl+D (EOF) en una línea nueva.
# Luego, guarda el config en ~/docker/docker-compose.yml.
echo "Pegue el texto completo del archivo de configuración de docker-compose.yml (copie y pegue todo el contenido). Esto sobrescribirá el existente."
echo "Cuando termine, presione Enter en una línea nueva y luego Ctrl+D (EOF) para continuar."
DOCKER_COMPOSE_CONFIG=$(cat)
if [ -z "$DOCKER_COMPOSE_CONFIG" ]; then
    echo "ERROR: El archivo de configuración de docker-compose.yml está vacío."
    exit 1
fi
echo "$DOCKER_COMPOSE_CONFIG" > ~/docker/docker-compose.yml
check_error
echo "Archivo de configuración de docker-compose actualizado en ~/docker/docker-compose.yml"

# Re-asignar permisos después de escribir archivos en ~/docker (con sudo para forzar)
sudo chmod -R 755 ~/docker
check_error

# VERIFICACIÓN: Chequea jellyfin/config
if [ -d ~/docker/jellyfin/config ]; then
    echo "Verificando ownership en ~/docker/jellyfin/config:"
    ls -la ~/docker/jellyfin/config | head -3
    if ! ls -la ~/docker/jellyfin/config | grep -q "tux.*tux"; then
        echo "ERROR: Ownership no es tux:tux en jellyfin/config. Fijar manual."
        exit 1
    fi
    echo "OK: Ownership correcto."
else
    echo "Nota: jellyfin/config no existe aún (se creará en syncs)."
fi

echo "Configuración de archivos completada como usuario '\''tux'\''!"
'

# Verificar si su falló
if [ $? -ne 0 ]; then
    echo "ERROR: La ejecución como usuario 'tux' falló."
    exit 1
fi

# ========================================
# FIX POST-SU: Re-forzar ownership como root después de escribir archivos
# ========================================
echo "Re-forzando ownership a tux:tux después de config de archivos..."
chown -R tux:tux "$DOCKER_DIR"
check_error

# Post-final clean
if [ -d "$JELLYFIN_CONFIG" ]; then
    chown -R tux:tux "$JELLYFIN_CONFIG"
    check_error
    find "$JELLYFIN_CONFIG" -name "*.partial" -delete || true
fi

# ========================================
# PASO OPCIONAL: Agregar 'tux' al grupo docker para usar Docker sin sudo (como root)
# ========================================
echo "¿Deseas agregar 'tux' al grupo docker para que pueda usar Docker sin sudo? (y/n): "
read -r ADD_TO_DOCKER_GROUP
if ! validate_yn "$ADD_TO_DOCKER_GROUP"; then
    exit 1
fi

if [[ "$ADD_TO_DOCKER_GROUP" =~ ^[Yy]$ ]]; then
    # Verificar si ya está en el grupo docker
    if ! groups tux | grep -q docker; then
        echo "Agregando 'tux' al grupo docker..."
        usermod -aG docker tux
        check_error
        echo "Usuario 'tux' agregado al grupo docker. Nota: 'tux' debe reloguear (cerrar sesión y volver a entrar) para que los cambios surtan efecto."
    else
        echo "'tux' ya está en el grupo docker. Omitiendo."
    fi
else
    echo "No se agregó 'tux' al grupo docker. Puedes usar Docker con sudo."
fi

# ========================================
# ÚLTIMO PASO: Ejecutar docker compose up -d en el directorio docker (como tux) - CONDICIONAL
# ========================================
# Este es el último paso: Pregunta si ejecutar, y si sí, lo hace como tux (usando sudo para evitar problemas de permisos/rel login)
echo "¿Deseas ejecutar docker compose up -d ahora como usuario 'tux' en ~/docker? (y/n): "
read -r RUN_COMPOSE
if ! validate_yn "$RUN_COMPOSE"; then
    exit 1
fi

if [[ "$RUN_COMPOSE" =~ ^[Yy]$ ]]; then
    echo "Ejecutando docker compose up -d en ~/docker como 'tux' (reiniciará si hay cambios)..."
    su - tux -c '
    set -u
    cd ~/docker
    if [ $? -ne 0 ]; then
        echo "ERROR: No se pudo cambiar al directorio ~/docker."
        exit 1
    fi
    sudo docker compose up -d
    if [ $? -ne 0 ]; then
        echo "ERROR: docker compose up -d falló."
        exit 1
    fi
    echo "Servicios de Docker Compose iniciados/actualizados exitosamente."
    '
    check_error  # Verifica el exit code del su -c
else
    echo "Omitiendo ejecución de docker compose up -d."
fi

echo "Script de setup finalizado. Ahora puedes conectarte como 'tux'."
# Nota: Para remover NOPASSWD después del setup, borra /etc/sudoers.d/tux manualmente si es necesario.
# Recomendación: Ejecuta ./configurarDockerRclone.sh como tux para instalar/actualizar Docker y rclone si no lo has hecho.
