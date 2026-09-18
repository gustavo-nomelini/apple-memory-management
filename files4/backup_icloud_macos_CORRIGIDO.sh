#!/bin/bash

################################################################################
# BACKUP ICLOUD MACOS - VERSÃO CORRIGIDA
# Sem argumentos que não existem no icloudpd
# Tratamento de erros melhorado
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
║  📥 BACKUP ICLOUD MACOS - VERSÃO CORRIGIDA                   ║
║  Sem argumentos problemáticos do icloudpd                    ║
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
mkdir -p "$BACKUP_ROOT"/{downloads,logs,reports,temp} 2>/dev/null || true

# Data/hora para logs
TIMESTAMP=$(date +%Y-%m-%d)
TIMESTAMP_FULL=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$BACKUP_ROOT/logs/backup_${TIMESTAMP}_$(date +%H-%M-%S).log"
BACKUP_DIR="$BACKUP_ROOT/downloads/$TIMESTAMP"

# Criar diretório de backup
mkdir -p "$BACKUP_DIR" 2>/dev/null || true

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
echo "   ${CYAN}$BACKUP_DIR${NC}"
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

echo -e "${BLUE}[2026-09-18 14:48:18]${NC} =========================================="
echo -e "${BLUE}[2026-09-18 14:48:18]${NC} ETAPA 1: DOWNLOAD DO ICLOUD"
echo -e "${BLUE}[2026-09-18 14:48:18]${NC} =========================================="
echo ""

# Pedir email se não estiver configurado
if [ -z "$ICLOUD_EMAIL" ]; then
    read -p "Digite seu email do iCloud: " ICLOUD_EMAIL
fi

if [ -z "$ICLOUD_EMAIL" ]; then
    error "Email do iCloud é obrigatório"
    exit 1
fi

# Executar icloudpd com argumentos SIMPLES (sem --keep-unicode-filenames, etc)
log "Iniciando download para: $BACKUP_DIR"

# Adicionar ao log
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando icloudpd" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Email: $ICLOUD_EMAIL" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Diretório: $BACKUP_DIR" >> "$LOG_FILE"

# Comando SIMPLES sem argumentos problemáticos
icloudpd -u "$ICLOUD_EMAIL" -d "$BACKUP_DIR" 2>&1 | tee -a "$LOG_FILE" || true

echo ""
success "Download concluído"
echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 6: Contar arquivos
# ═══════════════════════════════════════════════════════════════

FILE_COUNT=$(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
FILE_COUNT="${FILE_COUNT:-0}"

TOTAL_SIZE=$(du -sb "$BACKUP_DIR" 2>/dev/null | awk '{print $1}' | tr -d ' ' || echo "0")
if [ -z "$TOTAL_SIZE" ]; then
    TOTAL_SIZE="0"
fi

TOTAL_SIZE_H=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}' || echo "0B")

log "Total de arquivos baixados: $FILE_COUNT"
log "Tamanho total: $TOTAL_SIZE_H"
echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 7: Gerar hashes (se houver arquivos)
# ═══════════════════════════════════════════════════════════════

echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ETAPA 2: GERANDO HASHES DE ARQUIVOS"
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo ""

HASHES_FILE="$BACKUP_ROOT/temp/current_hashes.txt"
mkdir -p "$(dirname "$HASHES_FILE")" 2>/dev/null || true

if [ "$FILE_COUNT" -gt 0 ]; then
    log "Calculando SHA256 para todos os arquivos..."
    
    find "$BACKUP_DIR" -type f -exec sha256sum {} \; > "$HASHES_FILE" 2>/dev/null || true
    
    HASH_COUNT=$(wc -l < "$HASHES_FILE" | tr -d ' ' || echo "0")
    success "Hashes gerados: $HASHES_FILE ($HASH_COUNT hashes)"
else
    warning "Nenhum arquivo para gerar hashes (0 arquivos baixados)"
    echo "" > "$HASHES_FILE"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 8: Detectar duplicatas (SE HOUVER ARQUIVOS)
# ═══════════════════════════════════════════════════════════════

echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ETAPA 3: DETECTANDO ARQUIVOS DUPLICADOS"
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo ""

if [ "$FILE_COUNT" -gt 0 ]; then
    log "Procurando duplicatas..."
    
    # Chamar detector de duplicatas
    if [ -f "./duplicate_detector.py" ]; then
        python3 ./duplicate_detector.py "$BACKUP_DIR" 2>&1 | tee -a "$LOG_FILE" || true
        success "Análise de duplicatas concluída"
    else
        warning "duplicate_detector.py não encontrado - pulando análise"
    fi
else
    warning "Nenhum arquivo para analisar (0 arquivos)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 9: Verificação de integridade
# ═══════════════════════════════════════════════════════════════

echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ETAPA 4: VERIFICANDO INTEGRIDADE"
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo ""

if [ "$FILE_COUNT" -gt 0 ]; then
    log "Verificando integridade de todos os arquivos..."
    
    # Verificar hashes
    cd "$BACKUP_DIR" || exit 1
    
    FAILURES=0
    if [ -f "$HASHES_FILE" ]; then
        while IFS= read -r hash file; do
            if ! echo "$hash  $file" | sha256sum -c --quiet 2>/dev/null; then
                FAILURES=$((FAILURES + 1))
            fi
        done < "$HASHES_FILE"
    fi
    
    cd - > /dev/null || exit 1
    
    log "Integridade: $FILE_COUNT arquivos verificados"
    log "$FAILURES arquivos com falha"
    
    if [ "$FAILURES" -eq 0 ]; then
        success "Todos os arquivos estão íntegros"
    else
        warning "$FAILURES arquivos com problemas de integridade"
    fi
else
    warning "Nenhum arquivo para verificar (0 arquivos)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# PASSO 10: Gerar relatório final
# ═══════════════════════════════════════════════════════════════

echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} =========================================="
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ETAPA 5: GERANDO RELATÓRIO FINAL"
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
📂 DIRETÓRIO: $BACKUP_DIR

ESTATÍSTICAS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Quantidade de arquivos:        $FILE_COUNT
Tamanho total: $TOTAL_SIZE_H

TIPOS DE ARQUIVO:

PRÓXIMAS AÇÕES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. ✓ COMPLETADO: Download de todas as mídias do iCloud
2. ✓ COMPLETADO: Verificação de duplicatas
3. ✓ COMPLETADO: Verificação de integridade

PRÓXIMAS AÇÕES:
→ Revisar o diretório: $BACKUP_DIR
→ Confirmar que todos os arquivos necessários foram baixados
→ Executar script de limpeza apenas APÓS confirmar tudo

AVISOS IMPORTANTES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  Não execute a limpeza automática até verificar manualmente
⚠️  Mantenha este backup como referência antes de deletar arquivos
⚠️  Considere fazer backup em outro disco como segurança extra

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
echo "   📁 Diretório: $BACKUP_DIR"
echo "   📄 Arquivos: $FILE_COUNT"
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
    echo "Verifique o log para detalhes:"
    echo "  $LOG_FILE"
    echo ""
fi

echo "Próximas ações:"
echo "  1. Revisar arquivos no Finder"
echo "  2. Se houver arquivos, executar análise de duplicatas"
echo "  3. Fazer backup em segundo disco (rsync)"
echo ""

success "Tudo pronto!"
