#!/bin/bash

# Script de setup: Crea usuario tux (si no existe), asigna sudo, crea directorio docker, y configura rclone.conf y docker-compose.yml COMO tux
# Uso: ./setup-tux-configs.sh  (ejecutar como root; te pedirá contraseña ANTES de crear tux si no existe, y luego configs interactivas)
# Al final, regresa a root.
# Verificación de errores: Se agregan chequeos de exit code después de comandos críticos. Si falla, muestra error y sale.
# Validación de entrada: Verifica que se ejecute como root, contraseña mínima de 8 chars, configs no vacíos.
# Ajuste: Si el usuario 'tux' ya existe, omite la creación y configuración de contraseña/grupo sudo.
# Nota: Siempre pide configs para permitir sobrescritura/actualización. Ejecuta docker compose up -d al final.

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
# PASO INICIAL: Verificar si usuario 'tux' ya existe
# ========================================
TUX_EXISTS=false
if id "tux" &>/dev/null; then
    echo "Usuario 'tux' ya existe. Omitiendo creación."
    TUX_EXISTS=true
else
    # Solicitar contraseña ANTES de crear el usuario
    echo "El usuario 'tux' no existe. Se creará ahora."
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
# CONFIGURACIÓN DE SUDO NOPASSWD PARA TUX (temporal para prompts interactivos en su -c)
# ========================================
echo "Configurando sudo sin contraseña para 'tux' (temporal para setup)..."
echo "tux ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/tux
check_error
chmod 0440 /etc/sudoers.d/tux
check_error
echo "Configuración de sudoers aplicada."

# ========================================
# PASO PRINCIPAL: Configurar directorio, archivos y ejecutar compose como 'tux'
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
# GRUPO 1: Crear directorio docker en /home/tux/ (como tux)
# ========================================
echo "Creando directorio /home/tux/docker si no existe..."
mkdir -p ~/docker
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

# ========================================
# GRUPO 4: Ejecutar docker compose up -d en el directorio docker (como tux)
# ========================================
# Este grupo cambia al directorio ~/docker y ejecuta docker compose up -d para iniciar los servicios en background.
# Usa sudo para permisos de Docker (asumiendo que tux no está en el grupo docker aún).
echo "¿Deseas ejecutar docker compose up -d ahora? (y/n): "
read -r RUN_COMPOSE
if [[ "$RUN_COMPOSE" =~ ^[Yy]$ ]]; then
    echo "Ejecutando docker compose up -d en ~/docker (reiniciará si hay cambios)..."
    cd ~/docker
    check_error
    sudo docker compose up -d
    check_error
    echo "Servicios de Docker Compose iniciados/actualizados."
else
    echo "Omitiendo ejecución de docker compose up -d."
fi

echo "Configuración completada como usuario '\''tux'\''!"
'

# Verificar si su falló
if [ $? -ne 0 ]; then
    echo "ERROR: La ejecución como usuario 'tux' falló."
    exit 1
fi

# ========================================
# PASO FINAL: Opcional - Agregar 'tux' al grupo docker para usar Docker sin sudo (como root)
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

echo "Script de setup finalizado. Ahora puedes conectarte como 'tux'."
# Nota: Para remover NOPASSWD después del setup, borra /etc/sudoers.d/tux manualmente si es necesario.
# Recomendación: Ejecuta ./configurarDockerRclone.sh como tux para instalar/actualizar Docker y rclone si no lo has hecho.
