#!/bin/bash

# Script de instalación: Instala/actualiza Docker y rclone como usuario actual (ejecutar como tux o root con sudo)
# Uso: ./install-docker-rclone.sh  (ejecutar como tux; usa sudo para privilegios)
# Verificación: Salta instalación si ya existe, pero actualiza paquetes y configs si procede.
# Nota: No maneja creación de usuario tux, directorio docker, ni configs de rclone/docker-compose.

set -u  # Trata variables no definidas como error

# Función para verificar errores
check_error() {
    if [ $? -ne 0 ]; then
        echo "ERROR: El comando anterior falló. Abortando script."
        exit 1
    fi
}

# ========================================
# VALIDACIÓN INICIAL: Verificar dependencias básicas
# ========================================
if [ "$EUID" -eq 0 ]; then
    echo "Ejecutando como root. Usando sudo innecesario."
    USE_SUDO=""
else
    USE_SUDO="sudo"
    echo "Ejecutando como usuario no-root. Usando sudo para comandos privilegiados."
fi

# ========================================
# GRUPO 0: Actualizar paquetes del sistema (siempre, para posibles actualizaciones)
# ========================================
echo "Actualizando paquetes del sistema..."
$USE_SUDO apt-get update
check_error
$USE_SUDO apt-get upgrade -y
check_error

# ========================================
# GRUPO 1: Actualizar paquetes e instalar dependencias básicas para repositorios
# ========================================
# Este grupo actualiza la lista de paquetes y instala herramientas necesarias para manejar claves GPG y descargas seguras.
# ca-certificates asegura conexiones HTTPS válidas; curl para descargar el key de Docker.
echo "Verificando dependencias básicas (ca-certificates y curl)..."
if ! dpkg -l | grep -q ca-certificates || ! dpkg -l | grep -q curl; then
    echo "Instalando dependencias..."
    $USE_SUDO apt-get install -y ca-certificates curl
    check_error
else
    echo "Dependencias ya instaladas. Omitiendo."
fi

# ========================================
# GRUPO 2: Configurar directorio de keyrings y descargar clave GPG de Docker
# ========================================
# Este grupo crea un directorio seguro para claves GPG de repositorios de terceros y descarga la clave oficial de Docker.
# -m 0755: permisos de directorio (dueño escribe, grupo/otros leen/ejecutan).
# -fsSL: flags de curl para fail silent, show errors, location follow, silent.
# chmod a+r: hace la clave legible por todos (necesario para apt usar signed-by).
echo "Verificando clave GPG de Docker..."
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    echo "Configurando keyrings y descargando clave GPG de Docker..."
    $USE_SUDO install -m 0755 -d /etc/apt/keyrings
    check_error
    $USE_SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    check_error
    $USE_SUDO chmod a+r /etc/apt/keyrings/docker.asc
    check_error
else
    echo "Clave GPG de Docker ya configurada. Omitiendo."
fi

# ========================================
# GRUPO 3: Agregar repositorio oficial de Docker a las fuentes de APT
# ========================================
# Este grupo genera dinámicamente la línea del repositorio Docker basada en la arquitectura (amd64/arm64/etc.) y la versión de Ubuntu.
# $(dpkg --print-architecture): detecta arch automáticamente.
# CODENAME: se computa explícitamente aquí para expansión correcta.
# signed-by=/etc/apt/keyrings/docker.asc: usa la clave para verificar paquetes.
# tee > /dev/null: escribe al archivo sin output en consola.
# Nota: $USE_SUDO tee para escribir en /etc/.
CODENAME=$( . /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME} )
echo "Verificando repositorio de Docker..."
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo "Agregando repositorio de Docker con codename: $CODENAME..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $CODENAME stable" | \
      $USE_SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
    check_error
    $USE_SUDO apt-get update
    check_error
else
    echo "Repositorio de Docker ya agregado. Actualizando paquetes..."
    $USE_SUDO apt-get update
    check_error
fi

# ========================================
# GRUPO 4: Actualizar paquetes nuevamente e instalar componentes de Docker
# ========================================
# Este grupo refresca la lista de paquetes (para incluir el nuevo repo) e instala Docker CE y sus plugins.
# -y: asume yes a prompts.
# Paquetes: docker-ce (motor), docker-ce-cli (CLI), containerd.io (runtime), docker-buildx-plugin (buildx), docker-compose-plugin (compose v2).
echo "Verificando instalación de Docker..."
if ! dpkg -l | grep -q docker-ce; then
    echo "Instalando Docker..."
    $USE_SUDO apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_error
else
    echo "Docker ya instalado. Actualizando si es necesario..."
    $USE_SUDO apt-get -y upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_error
fi

# ========================================
# GRUPO 5: Iniciar el servicio de Docker si no está activo
# ========================================
# Este grupo verifica e inicia el daemon de Docker.
# start: inicia si no corre; no falla si ya está activo (a diferencia de restart).
echo "Verificando servicio de Docker..."
if ! $USE_SUDO systemctl is-active --quiet docker; then
    echo "Iniciando servicio de Docker..."
    $USE_SUDO systemctl start docker
    check_error
else
    echo "Servicio de Docker ya activo. Omitiendo."
fi

# ========================================
# GRUPO 6: Instalar rclone
# ========================================
# Este grupo descarga e instala rclone usando el script oficial de instalación.
# curl descarga el script de instalación; | $USE_SUDO bash lo ejecuta con privilegios.
# Nota: Esto instala rclone globalmente.
echo "Verificando instalación de rclone..."
if ! command -v rclone >/dev/null 2>&1; then
    echo "Instalando rclone..."
    curl https://rclone.org/install.sh | $USE_SUDO bash
    check_error
else
    echo "rclone ya instalado. Omitiendo."
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
    $USE_SUDO curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
    check_error
    $USE_SUDO mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
    check_error
    $USE_SUDO chmod +x /usr/local/bin/sops
    check_error
else
    echo "sops ya instalado. Omitiendo."
fi
if ! command -v age >/dev/null 2>&1; then
    echo "Instalando age..."
    $USE_SUDO apt-get update
    check_error
    $USE_SUDO apt-get install -y age
    check_error
else
    echo "age ya instalado. Omitiendo."
fi

# ========================================
# GRUPO 8: Descargar script de configuración adicional para Docker y rclone
# ========================================
# Este grupo descarga el script configurarDockerRclone.sh desde el repositorio GitHub y lo hace ejecutable.
# Se descarga en el directorio actual (ejecutar como tux para que quede en ~tux).
# Verifica si ya existe para evitar re-descargas innecesarias.
echo "Verificando descarga del script configurarDockerRclone.sh..."
if [ ! -f configurarDockerRclone.sh ]; then
    echo "Descargando script de configuración adicional..."
    $USE_SUDO curl -LO https://raw.githubusercontent.com/leosuaar/test/main/configurarDockerRclone.sh -o configurarDockerRclone.sh
    check_error
    $USE_SUDO mv configurarDockerRclone.sh /usr/local/bin/configurarsistema
    check_error
    chmod +x /usr/local/bin/configurarsistema
    check_error
    echo "Script descargado y hecho ejecutable. Puedes ejecutarlo manualmente después (ej: ./configurarDockerRclone.sh)."
else
    echo "Script configurarDockerRclone.sh ya existe. Omitiendo descarga."
fi

echo "Instalación/actualización de Docker, rclone, sops y age completada!"
echo "Nota: Para usar Docker sin sudo, agrega el usuario actual al grupo docker (ej: sudo usermod -aG docker $USER) y reloguea."
