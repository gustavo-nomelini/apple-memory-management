#!/bin/bash

################################################################################
# BACKUP ICLOUD MACOS - ORGANIZAÇÃO INTELIGENTE
# Opção 1: Pasta única
# Opção 2: Organizar por ano
# Opção 3: Organizar por ano/mês
################################################################################

set -uo pipefail

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# BANNER
clear
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║  📥 BACKUP ICLOUD MACOS - ORGANIZAÇÃO INTELIGENTE            ║
║  Escolha: Pasta única, por ano, ou por ano/mês               ║
╚═══════════════════════════════════════════════════════════════╝

EOF

# FUNÇÕES
log() {
    echo -e "${BLUE}[*]${NC} $*"
}

success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

error() {
    echo -e "${RED}[✗]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[⚠]${NC} $*"
}

# ═══════════════════════════════════════════════════════════════

# Carregar configuração
if [ -f "$HOME/.icloudpd_volume_config" ]; then
    source "$HOME/.icloudpd_volume_config"
fi

# Valores padrão
BACKUP_VOLUME="${BACKUP_VOLUME:-$HOME}"
BACKUP_ROOT="${BACKUP_ROOT:-$BACKUP_VOLUME/icloud_backups}"
ICLOUD_EMAIL="${ICLOUD_USERNAME:-}"

# Criar diretórios
mkdir -p "$BACKUP_ROOT"/{logs,reports,temp} 2>/dev/null || true

# Data/hora para logs
TIMESTAMP=$(date +%Y-%m-%d)
TIMESTAMP_FULL=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$BACKUP_ROOT/logs/backup_${TIMESTAMP}_$(date +%H-%M-%S).log"

# ═══════════════════════════════════════════════════════════════
# ESCOLHER ESTRUTURA DE PASTAS
# ═══════════════════════════════════════════════════════════════

echo -e "${CYAN}📁 ESCOLHA A ORGANIZAÇÃO DE PASTAS:${NC}"
echo ""
echo "1) Pasta única (recomendado)"
echo "   └─ Tudo em: /icloud_backups/media/"
echo ""
echo "2) Organizar por ano/mês"
echo "   └─ Estrutura: /icloud_backups/2024/01/"
echo "   └─            /icloud_backups/2024/02/"
echo ""

read -p "Opção (1-2) [padrão 1]: " ORGANIZATION
ORGANIZATION="${ORGANIZATION:-1}"

case "$ORGANIZATION" in
    1)
        ORG_MODE="unique"
        ORG_NAME="Pasta única"
        FOLDER_STRUCTURE="none"
        ;;
    2)
        ORG_MODE="by_year_month"
        ORG_NAME="Por ano/mês"
        FOLDER_STRUCTURE="{:%Y/%m}"
        ;;
    *)
        ORG_MODE="unique"
        ORG_NAME="Pasta única"
        FOLDER_STRUCTURE="none"
        ;;
esac

# O icloudpd cria a estrutura diretamente durante o download.
BACKUP_DIR="$BACKUP_ROOT/media"

# Criar diretório de backup
mkdir -p "$BACKUP_DIR" 2>/dev/null || true

echo ""
log "Organização: $ORG_NAME"
echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 1: Verificar pré-requisitos
# ═══════════════════════════════════════════════════════════════

log "Verificando pré-requisitos..."

if ! command -v icloudpd &> /dev/null; then
    error "icloudpd não encontrado. Instale com: pip3 install icloudpd"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    error "Python 3 não encontrado"
    exit 1
fi

success "Pré-requisitos OK"
echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 2: Mostrar informações do volume
# ═══════════════════════════════════════════════════════════════

echo "📱 Volume: ${CYAN}$(basename $BACKUP_VOLUME)${NC}"
if [ "$BACKUP_VOLUME" != "$HOME" ]; then
    echo "🔌 Device: $(diskutil info "$BACKUP_VOLUME" 2>/dev/null | grep 'Device Node' | awk '{print $3}' || echo 'N/A')"
fi
echo "📍 Caminho: $BACKUP_VOLUME"
echo ""

echo "💾 Espaço:"
df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print "   Total: " $2; print "   Usado: " $3; print "   Disponível: " $4}'
echo ""

echo "📂 Backup será criado em:"
if [ "$ORG_MODE" = "unique" ]; then
    echo "   ${CYAN}$BACKUP_DIR${NC}"
else
    echo "   ${CYAN}$BACKUP_DIR/YYYY/MM/${NC} (estrutura por ano/mês)"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 3: Verificar espaço
# ═══════════════════════════════════════════════════════════════

AVAILABLE=$(df "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d ' ')
AVAILABLE_GB=$((AVAILABLE / 1024 / 1024))

log "Espaço disponível em $BACKUP_VOLUME: ${AVAILABLE_GB}GB"

if [ "$AVAILABLE_GB" -lt 10 ]; then
    error "Espaço insuficiente! Precisa de pelo menos 10GB"
    exit 1
fi

success "Todos os pré-requisitos atendidos"
echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 4: Confirmação final
# ═══════════════════════════════════════════════════════════════

echo -e "${YELLOW}[⚠]${NC} VERIFICAÇÃO FINAL"
echo ""
echo "Volume e localização estão corretos? (s/N): " 
read -r CONFIRM

if [[ "$CONFIRM" != "s" ]]; then
    log "Operação cancelada"
    exit 1
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 5: Download do iCloud
# ═══════════════════════════════════════════════════════════════

echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ETAPA 1: DOWNLOAD DO ICLOUD"
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo ""

# Pedir email se não estiver configurado
if [ -z "$ICLOUD_EMAIL" ]; then
    read -p "Digite seu email do iCloud: " ICLOUD_EMAIL
fi

if [ -z "$ICLOUD_EMAIL" ]; then
    error "Email do iCloud é obrigatório"
    exit 1
fi

log "Iniciando download para: $BACKUP_DIR"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Email: $ICLOUD_EMAIL" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Diretório: $BACKUP_DIR" >> "$LOG_FILE"

# O valor `none` evita a estrutura padrão diária do icloudpd.
icloudpd -u "$ICLOUD_EMAIL" -d "$BACKUP_DIR" \
    --folder-structure "$FOLDER_STRUCTURE" 2>&1 | tee -a "$LOG_FILE" || true

echo ""
success "Download concluído"
echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 7: Contar arquivos
# ═══════════════════════════════════════════════════════════════

FILE_COUNT=$(find "$BACKUP_ROOT/media" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ -z "$FILE_COUNT" ] || [ "$FILE_COUNT" = "0" ]; then
    FILE_COUNT=$(find "$BACKUP_ROOT" -type f -not -path "*/logs/*" -not -path "*/reports/*" -not -path "*/temp/*" 2>/dev/null | wc -l | tr -d ' ')
fi

TOTAL_SIZE=$(du -sb "$BACKUP_ROOT/media" 2>/dev/null | awk '{print $1}' | tr -d ' ' || echo "0")
if [ -z "$TOTAL_SIZE" ] || [ "$TOTAL_SIZE" = "0" ]; then
    TOTAL_SIZE=$(du -sb "$BACKUP_ROOT" 2>/dev/null | awk '{print $1}' | tr -d ' ' || echo "0")
fi

TOTAL_SIZE_H=$(du -sh "$BACKUP_ROOT/media" 2>/dev/null | awk '{print $1}' || du -sh "$BACKUP_ROOT" 2>/dev/null | awk '{print $1}' || echo "0B")

log "Total de arquivos baixados: $FILE_COUNT"
log "Tamanho total: $TOTAL_SIZE_H"
echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 8: Gerar relatório final
# ═══════════════════════════════════════════════════════════════

echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ETAPA 2: RELATÓRIO FINAL"
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo ""

REPORT_FILE="$BACKUP_ROOT/reports/report_${TIMESTAMP}_$(date +%H-%M-%S).txt"
mkdir -p "$(dirname "$REPORT_FILE")" 2>/dev/null || true

cat > "$REPORT_FILE" << EOFREPORT
╔════════════════════════════════════════════════════════════════╗
║        RELATÓRIO FINAL DE BACKUP DO ICLOUD                    ║
╚════════════════════════════════════════════════════════════════╝

📅 DATA/HORA: $TIMESTAMP_FULL
📁 VOLUME: $(basename "$BACKUP_VOLUME")
📂 ORGANIZAÇÃO: $ORG_NAME
📂 DIRETÓRIO: $BACKUP_ROOT

ESTATÍSTICAS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Quantidade de arquivos:        $FILE_COUNT
Tamanho total: $TOTAL_SIZE_H

ESTRUTURA:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PRÓXIMAS AÇÕES:
→ Revisar os arquivos no Finder
→ Confirmar que tudo foi baixado corretamente
→ Fazer backup em outro disco para redundância

ARQUIVO DE LOG:
$LOG_FILE

EOFREPORT

success "Relatório salvo em: $REPORT_FILE"
echo ""

# ═══════════════════════════════════════════════════════════════
# RESUMO FINAL
# ═══════════════════════════════════════════════════════════════

echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ BACKUP COMPLETADO COM SUCESSO!${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "📊 Resumo:"
echo "   📁 Organização: $ORG_NAME"
echo "   📂 Diretório: $BACKUP_ROOT"

if [ "$ORG_MODE" = "unique" ]; then
    echo "   📄 Todos os arquivos em: $BACKUP_ROOT/media/"
elif [ "$ORG_MODE" = "by_year" ]; then
    echo "   📄 Estrutura: $BACKUP_ROOT/YYYY/"
elif [ "$ORG_MODE" = "by_year_month" ]; then
    echo "   📄 Estrutura: $BACKUP_ROOT/YYYY/MM/"
fi

echo "   📄 Total: $FILE_COUNT arquivos"
echo "   💾 Tamanho: $TOTAL_SIZE_H"
echo ""

if [ "$FILE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  ATENÇÃO: Nenhum arquivo foi baixado!${NC}"
    echo ""
    echo "Possíveis causas:"
    echo "  1. Nenhuma foto no iCloud"
    echo "  2. Autenticação falhou (verifique 2FA)"
    echo "  3. Problemas de conectividade"
    echo ""
fi

echo "Próximas ações:"
echo "  1. Abrir pasta no Finder:"
echo "     open \"$BACKUP_ROOT\""
echo ""
echo "  2. Fazer backup em segundo disco:"
echo "     rsync -av \"$BACKUP_ROOT/media/\" /Volumes/DISCO_SEGUNDO/"
echo ""

success "Tudo pronto!"
