#!/bin/bash

set -e

# --- CONFIGURAÇÃO DO REPOSITÓRIO ---
GITHUB_USER="bernardo58247"
GITHUB_REPO="ppl-programming-language"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$BRANCH/src/ppl.cpp"

# 1. menu de seleção de idioma
echo "=========================================="
echo "  PPL (Portuguese Programming Language)  "
echo "=========================================="
echo "Select installation language / Selecione o idioma de instalação:"
echo "1) Português (Brasil)"
echo "2) English"
read -p "Option/Opção [1-2]: " LANG_OPT

if [ "$LANG_OPT" = "2" ]; then
    MSG_TITLE="=== PPL Installer (C++) ==="
    MSG_ENV_TERMUX="-> Detected environment: Termux (Android)"
    MSG_ENV_LINUX="-> Detected environment: Linux"
    MSG_NO_COMPILER="-> No C++ compiler found. Installing 'clang'..."
    MSG_NO_DOWNLOADER="-> Installing 'wget'..."
    MSG_DOWNLOADING="-> Downloading source code from GitHub..."
    MSG_USING_COMPILER="-> Using compiler:"
    MSG_COMPILING="-> Compiling PPL..."
    MSG_INSTALLING="-> Installing binary to"
    MSG_SUCCESS="\nInstallation completed successfully!\nRun your scripts using: ppl script_name.ppls"
    MSG_ERR_DL="Error: Failed to download ppl.cpp from GitHub."
else
    MSG_TITLE="=== Instalador do PPL (C++) ==="
    MSG_ENV_TERMUX="-> Ambiente detectado: Termux (Android)"
    MSG_ENV_LINUX="-> Ambiente detectado: Linux"
    MSG_NO_COMPILER="-> Nenhum compilador C++ encontrado. Instalando 'clang'..."
    MSG_NO_DOWNLOADER="-> Instalando 'wget'..."
    MSG_DOWNLOADING="-> Baixando código fonte do GitHub..."
    MSG_USING_COMPILER="-> Usando compilador:"
    MSG_COMPILING="-> Compilando PPL..."
    MSG_INSTALLING="-> Instalando binário em"
    MSG_SUCCESS="\nInstalação concluída com sucesso!\nRode seus scripts usando: ppl nome_do_script.ppls"
    MSG_ERR_DL="Erro: Falha ao baixar o arquivo ppl.cpp do GitHub."
fi

echo -e "\n$MSG_TITLE"

# 2. detecta ambiente (Termux vs Linux)
if [ -d "/data/data/com.termux" ] || [ -n "$PREFIX" ]; then
    IS_TERMUX=true
    BIN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
    SUDO=""
    echo "$MSG_ENV_TERMUX"
else
    IS_TERMUX=false
    BIN_DIR="/usr/local/bin"
    [ "$(id -u)" -ne 0 ] && SUDO="sudo" || SUDO=""
    echo "$MSG_ENV_LINUX"
fi

# 3. função utilitária para instalar pacotes dependentes
instalar_pacote() {
    local pkg=$1
    if [ "$IS_TERMUX" = true ]; then
        pkg update -y && pkg install -y "$pkg"
    elif command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update && $SUDO apt-get install -y "$pkg"
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y "$pkg"
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm "$pkg"
    else
        echo "Erro: Gerenciador de pacotes não suportado para instalar $pkg."
        exit 1
    fi
}

# 4. garante ferramenta de download (wget ou curl)
if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    echo "$MSG_NO_DOWNLOADER"
    instalar_pacote "wget"
fi

# 5. garante compilador C++ (g++ ou clang++)
if command -v g++ >/dev/null 2>&1; then
    CXX="g++"
elif command -v clang++ >/dev/null 2>&1; then
    CXX="clang++"
else
    echo "$MSG_NO_COMPILER"
    instalar_pacote "clang"
    CXX="clang++"
fi

echo "$MSG_USING_COMPILER $CXX"

# 6. cria diretório temporário para compilação isolada
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "$MSG_DOWNLOADING"
if command -v wget >/dev/null 2>&1; then
    wget -q "$RAW_URL" -O "$TMP_DIR/ppl.cpp" || { echo "$MSG_ERR_DL"; exit 1; }
else
    curl -sL "$RAW_URL" -o "$TMP_DIR/ppl.cpp" || { echo "$MSG_ERR_DL"; exit 1; }
fi

# 7. compilação otimizada (-O3 + strip de símbolos)
echo "$MSG_COMPILING"
$CXX -O3 -std=c++17 -s "$TMP_DIR/ppl.cpp" -o "$TMP_DIR/ppl"

# 8. instalação do binário
echo "$MSG_INSTALLING $BIN_DIR/ppl..."
$SUDO mkdir -p "$BIN_DIR"
$SUDO cp "$TMP_DIR/ppl" "$BIN_DIR/ppl"
$SUDO chmod +x "$BIN_DIR/ppl"

echo -e "$MSG_SUCCESS"
