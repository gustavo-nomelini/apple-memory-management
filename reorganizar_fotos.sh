#!/bin/bash

################################################################################
# REORGANIZAR FOTOS - CONVERTER PASTAS POR DIA EM ORGANIZAÇÃO INTELIGENTE
# Funciona com backups já baixados
################################################################################

set -uo pipefail

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║  📁 REORGANIZAR FOTOS DO BACKUP                             ║
║  Converter de pastas por dia em organização inteligente      ║
╚═══════════════════════════════════════════════════════════════╝

EOF

# Detectar caminho
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/icloud_backups}"
DOWNLOAD_DIR="$BACKUP_ROOT/downloads"

echo "📂 Procurando backups em: $DOWNLOAD_DIR"
echo ""

if [ ! -d "$DOWNLOAD_DIR" ]; then
    echo -e "${RED}❌ Diretório não encontrado: $DOWNLOAD_DIR${NC}"
    exit 1
fi

# Contar pastas
FOLDER_COUNT=$(find "$DOWNLOAD_DIR" -maxdepth 1 -type d ! -name "downloads" 2>/dev/null | wc -l)

if [ "$FOLDER_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Nenhuma pasta de backup encontrada${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Encontrado: $FOLDER_COUNT pastas de backup${NC}"
echo ""

# Escolher organização
echo -e "${CYAN}📁 ESCOLHA A NOVA ORGANIZAÇÃO:${NC}"
echo ""
echo "1) Pasta única (tudo em /media)"
echo "2) Organizar por ano"
echo "3) Organizar por ano/mês"
echo ""

read -p "Opção (1-3) [padrão 1]: " ORG_CHOICE
ORG_CHOICE="${ORG_CHOICE:-1}"

# Pedir confirmação
echo ""
echo -e "${YELLOW}⚠️  AVISO:${NC}"
echo "Este script vai:"
echo "  1. Ler todos os arquivos de backup"
echo "  2. Obter data de cada arquivo"
echo "  3. Mover para nova estrutura"
echo "  4. Deletar pastas vazias"
echo ""

read -p "Prosseguir? (s/N): " CONFIRM

if [[ "$CONFIRM" != "s" ]]; then
    echo "Cancelado"
    exit 1
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# FUNÇÃO: REORGANIZAR
# ═══════════════════════════════════════════════════════════════

reorganize() {
    local file_path="$1"
    local mode="$2"
    
    # Obter data do arquivo
    local file_year=$(date -r "$file_path" '+%Y' 2>/dev/null || echo "desconhecido")
    local file_month=$(date -r "$file_path" '+%m' 2>/dev/null || echo "00")
    
    # Criar diretório de destino
    if [ "$mode" = "unique" ]; then
        local dest_dir="$BACKUP_ROOT/media"
    elif [ "$mode" = "by_year" ]; then
        local dest_dir="$BACKUP_ROOT/$file_year"
    elif [ "$mode" = "by_year_month" ]; then
        local dest_dir="$BACKUP_ROOT/$file_year/$file_month"
    fi
    
    mkdir -p "$dest_dir" 2>/dev/null || return
    
    # Mover arquivo
    local filename=$(basename "$file_path")
    if mv "$file_path" "$dest_dir/$filename" 2>/dev/null; then
        echo "✓ $filename"
    else
        echo "✗ Erro ao mover: $filename"
    fi
}

# ═══════════════════════════════════════════════════════════════
# PROCESSAR ARQUIVOS
# ═══════════════════════════════════════════════════════════════

echo -e "${BLUE}[*] Reorganizando arquivos...${NC}"
echo ""

case "$ORG_CHOICE" in
    1)
        echo "Organizando em pasta única..."
        echo ""
        
        find "$DOWNLOAD_DIR" -type f | while read -r file; do
            reorganize "$file" "unique"
        done
        
        echo ""
        echo -e "${GREEN}✓ Estrutura final:${NC}"
        echo "  /icloud_backups/media/"
        ;;
    
    2)
        echo "Organizando por ano..."
        echo ""
        
        find "$DOWNLOAD_DIR" -type f | while read -r file; do
            reorganize "$file" "by_year"
        done
        
        echo ""
        echo -e "${GREEN}✓ Estrutura final:${NC}"
        echo "  /icloud_backups/2024/"
        echo "  /icloud_backups/2023/"
        echo "  /icloud_backups/2022/"
        ;;
    
    3)
        echo "Organizando por ano/mês..."
        echo ""
        
        find "$DOWNLOAD_DIR" -type f | while read -r file; do
            reorganize "$file" "by_year_month"
        done
        
        echo ""
        echo -e "${GREEN}✓ Estrutura final:${NC}"
        echo "  /icloud_backups/2024/01/"
        echo "  /icloud_backups/2024/02/"
        echo "  /icloud_backups/2024/03/"
        echo "  /icloud_backups/2023/..."
        ;;
    
    *)
        echo -e "${RED}Opção inválida${NC}"
        exit 1
        ;;
esac

# ═══════════════════════════════════════════════════════════════
# LIMPAR PASTAS VAZIAS
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "${BLUE}[*] Limpando pastas vazias...${NC}"

find "$DOWNLOAD_DIR" -type d -empty -delete 2>/dev/null || true

# Deletar pasta downloads se vazia
if [ ! "$(ls -A "$DOWNLOAD_DIR" 2>/dev/null)" ]; then
    rm -rf "$DOWNLOAD_DIR" 2>/dev/null || true
fi

echo -e "${GREEN}✓ Pastas vazias removidas${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# RESUMO
# ═══════════════════════════════════════════════════════════════

echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ REORGANIZAÇÃO CONCLUÍDA!${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

# Contar novo estado
NEW_FOLDER_COUNT=$(find "$BACKUP_ROOT" -maxdepth 1 -type d ! -name "icloud_backups" ! -name "logs" ! -name "reports" ! -name "temp*" ! -name "downloads" ! -name "*.sh" 2>/dev/null | wc -l)
FILE_COUNT=$(find "$BACKUP_ROOT" -type f ! -path "*/logs/*" ! -path "*/reports/*" ! -path "*/temp/*" 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_ROOT" 2>/dev/null | awk '{print $1}' || echo "?")

echo "📊 Resumo:"
echo "   📁 Pastas criadas: $NEW_FOLDER_COUNT"
echo "   📄 Arquivos: $FILE_COUNT"
echo "   💾 Tamanho total: $TOTAL_SIZE"
echo ""

echo "📂 Estrutura final:"
echo "   $BACKUP_ROOT/"
ls -1 "$BACKUP_ROOT" | grep -v -E "(logs|reports|temp|downloads|\.sh)" | while read -r item; do
    echo "   ├── $item/"
done

echo ""
echo -e "${GREEN}✓ Pronto! Suas fotos estão bem organizadas.${NC}"
echo ""

# Opção de visualizar
read -p "Abrir pasta no Finder? (s/N): " OPEN_FINDER

if [[ "$OPEN_FINDER" == "s" ]]; then
    open "$BACKUP_ROOT" 2>/dev/null || echo "Não foi possível abrir o Finder"
fi
