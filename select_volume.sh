#!/bin/bash

################################################################################
# SELETOR DE VOLUME - Simples e confiável
# Sem bugs, apenas selecionar o volume e pronto
################################################################################

set -euo pipefail

# CORES
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║  📁 SELETOR DE VOLUME                                        ║
║  Escolha onde guardar seus backups                           ║
╚═══════════════════════════════════════════════════════════════╝

EOF

echo "Volumes encontrados:"
echo ""

# Lista de volumes
declare -a VOLUMES
declare -a NAMES

idx=1

# Volume principal
VOLUMES[1]="$HOME"
NAMES[1]="Macintosh HD (Disco Principal)"
echo "  1) ${NAMES[1]}"
echo "     $(df -h "$HOME" | awk 'NR==2 {print $2}' || echo "?")"
echo ""
idx=$((idx + 1))

# Volumes externos
for volume in /Volumes/*; do
    if [ ! -L "$volume" ] 2>/dev/null && [ "$volume" != "/Volumes/Macintosh HD" ] && [ "$volume" != "/Volumes/Recovery" ] 2>/dev/null; then
        local name=$(basename "$volume")
        local size=$(df -h "$volume" 2>/dev/null | awk 'NR==2 {print $2}' || echo "?")
        local avail=$(df -h "$volume" 2>/dev/null | awk 'NR==2 {print $4}' || echo "?")
        
        VOLUMES[$idx]="$volume"
        NAMES[$idx]="$name"
        
        echo "  $idx) ${CYAN}$name${NC}"
        echo "     Tamanho: $size | Disponível: $avail"
        echo ""
        
        idx=$((idx + 1))
    fi
done

echo ""
read -p "${YELLOW}Qual volume usar? (Digite o número): ${NC}" choice

if [ -z "$choice" ] || [ -z "${VOLUMES[$choice]:-}" ]; then
    echo "❌ Opção inválida"
    exit 1
fi

SELECTED_VOLUME="${VOLUMES[$choice]}"
SELECTED_NAME="${NAMES[$choice]}"

echo ""
echo "✓ Selecionado: ${GREEN}$SELECTED_NAME${NC}"
echo "  Caminho: $SELECTED_VOLUME"
echo ""

# Validar escrita
if [ ! -w "$SELECTED_VOLUME" ]; then
    echo "❌ Sem permissão de escrita em: $SELECTED_VOLUME"
    echo ""
    echo "Tente:"
    echo "  sudo chmod 755 '$SELECTED_VOLUME'"
    exit 1
fi

echo "✓ Permissões OK"
echo ""

# Criar config
echo "Criando configuração..."
mkdir -p "$HOME/.config" 2>/dev/null || true

cat > "$HOME/.icloudpd_volume_config" << EOF
#!/bin/bash
# Configuração de Volume para Backup iCloud
# Volume selecionado: $SELECTED_NAME
# Data: $(date)

export BACKUP_VOLUME="$SELECTED_VOLUME"
export BACKUP_ROOT="\$BACKUP_VOLUME/icloud_backups"
export ICLOUD_USERNAME=""

EOF

echo "✓ Configuração salva"
echo ""

# Criar estrutura
echo "Criando estrutura de diretórios..."
mkdir -p "$SELECTED_VOLUME/icloud_backups"/{downloads,archive,duplicates,logs,reports,temp,cleanup_backups}
chmod 755 "$SELECTED_VOLUME/icloud_backups" 2>/dev/null || true

echo "✓ Estrutura criada"
echo ""

echo "╔═══════════════════════════════════════════════════════════╗"
echo "  ✓ PRONTO PARA FAZER BACKUP!"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Próximo comando:"
echo "  ${GREEN}chmod +x backup_icloud_macos.sh${NC}"
echo "  ${GREEN}./backup_icloud_macos.sh${NC}"
echo ""
echo "Ou use o atalho (se já configurado):"
echo "  ${GREEN}icloud-backup${NC}"
echo ""
