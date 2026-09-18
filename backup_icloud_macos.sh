#!/bin/bash

################################################################################
# BACKUP ICLOUD WORKFLOW - VERSÃO MACOS COM SUPORTE A VOLUMES
# Detecta automaticamente volumes e permite usar disco externo
################################################################################

set -euo pipefail

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# DETECÇÃO AUTOMÁTICA DE VOLUME
# ============================================================

detect_best_volume() {
    log "Detectando volumes disponíveis..."
    
    # Primeiro, verificar se há volume configurado
    if [ -f "$HOME/.icloudpd_volume_config" ]; then
        source "$HOME/.icloudpd_volume_config"
        if [ ! -z "${BACKUP_VOLUME:-}" ] && [ -w "$BACKUP_VOLUME" ]; then
            log "Usando volume configurado: $BACKUP_VOLUME"
            echo "$BACKUP_VOLUME"
            return 0
        fi
    fi
    
    # Se não houver, procurar por volumes externos
    local best_volume=""
    local best_space=0
    
    # Listar volumes
    for volume in /Volumes/*; do
        if [ -d "$volume" ] && [ -w "$volume" ] && [ "$volume" != "/Volumes/Recovery" ]; then
            local available=$(df "$volume" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
            if [ "$available" -gt "$best_space" ]; then
                best_volume="$volume"
                best_space=$available
            fi
        fi
    done
    
    # Se encontrou volume externo, usar
    if [ ! -z "$best_volume" ]; then
        log "Volume externo encontrado: $best_volume"
        echo "$best_volume"
        return 0
    fi
    
    # Caso contrário, usar home
    log "Nenhum volume externo, usando $HOME"
    echo "$HOME"
}

# ============================================================
# CONFIGURAÇÃO
# ============================================================

# Detectar volume
DETECTED_VOLUME=$(detect_best_volume)

# Permitir override via variável de ambiente
BACKUP_VOLUME="${BACKUP_VOLUME:-$DETECTED_VOLUME}"
BACKUP_ROOT="${BACKUP_ROOT:-$BACKUP_VOLUME/icloud_backups}"

DOWNLOAD_DIR="${BACKUP_ROOT}/downloads/$(date +%Y-%m-%d)"
ARCHIVE_DIR="${BACKUP_ROOT}/archive"
DUPLICATES_DIR="${BACKUP_ROOT}/duplicates"
LOG_FILE="${BACKUP_ROOT}/logs/backup_$(date +%Y-%m-%d_%H-%M-%S).log"
REPORT_FILE="${BACKUP_ROOT}/reports/report_$(date +%Y-%m-%d_%H-%M-%S).txt"

# ============================================================
# FUNÇÕES DE LOG
# ============================================================

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[✗]${NC} $*" | tee -a "${LOG_FILE}"
}

warning() {
    echo -e "${YELLOW}[⚠]${NC} $*" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${CYAN}ℹ${NC} $*" | tee -a "${LOG_FILE}"
}

# ============================================================
# CRIAR ESTRUTURA
# ============================================================

create_structure() {
    log "Criando estrutura de diretórios..."
    
    mkdir -p "${DOWNLOAD_DIR}" "${ARCHIVE_DIR}" "${DUPLICATES_DIR}" \
              "${BACKUP_ROOT}/logs" "${BACKUP_ROOT}/reports" "${BACKUP_ROOT}/temp"
    
    # Permissões
    chmod 750 "${BACKUP_ROOT}"
    chmod 755 "${BACKUP_ROOT}"/{downloads,archive,logs,reports}
    chmod 700 "${BACKUP_ROOT}"/{duplicates,temp}
    
    success "Estrutura criada"
}

# ============================================================
# VERIFICAR PRÉ-REQUISITOS
# ============================================================

check_requirements() {
    log "Verificando pré-requisitos..."
    
    local missing=0
    
    # Verificar acesso ao volume
    if [ ! -w "$BACKUP_VOLUME" ]; then
        error "Sem permissão de escrita em: $BACKUP_VOLUME"
        missing=1
    fi
    
    # Verificar espaço em disco
    local available=$(df "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    local available_gb=$((available / 1024 / 1024))
    
    log "Espaço disponível em $BACKUP_VOLUME: ${available_gb}GB"
    
    if [ "$available_gb" -lt 50 ]; then
        warning "Espaço baixo! (Recomendado: 100GB+)"
    fi
    
    # Verificar icloudpd
    if ! command -v icloudpd &> /dev/null; then
        error "icloudpd não encontrado"
        missing=1
    fi
    
    # Verificar Python
    if ! command -v python3 &> /dev/null; then
        error "Python3 não encontrado"
        missing=1
    fi
    
    # Verificar sha256sum
    if ! command -v sha256sum &> /dev/null && ! command -v shasum &> /dev/null; then
        error "sha256sum/shasum não encontrado"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        error "Dependências não atendidas"
        exit 1
    fi
    
    success "Todos os pré-requisitos atendidos"
}

# ============================================================
# EXIBIR INFORMAÇÕES DO VOLUME
# ============================================================

show_volume_info() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              INFORMAÇÕES DO VOLUME DE BACKUP               ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local volume_name=$(basename "$BACKUP_VOLUME")
    local volume_device=$(df "$BACKUP_VOLUME" | awk 'NR==2 {print $1}')
    local volume_size=$(df -h "$BACKUP_VOLUME" | awk 'NR==2 {print $2}')
    local volume_used=$(df -h "$BACKUP_VOLUME" | awk 'NR==2 {print $3}')
    local volume_available=$(df -h "$BACKUP_VOLUME" | awk 'NR==2 {print $4}')
    
    echo "📱 Volume: ${CYAN}$volume_name${NC}"
    echo "🔌 Device: $volume_device"
    echo "📍 Caminho: $BACKUP_VOLUME"
    echo ""
    echo "💾 Espaço:"
    echo "   Total: $volume_size"
    echo "   Usado: $volume_used"
    echo "   Disponível: $volume_available"
    echo ""
    echo "📂 Backup será criado em:"
    echo "   ${CYAN}${DOWNLOAD_DIR}${NC}"
    echo ""
}

# ============================================================
# CONFIRMAR ANTES DE COMEÇAR
# ============================================================

confirm_backup() {
    echo ""
    warning "VERIFICAÇÃO FINAL"
    echo ""
    
    read -p "Volume e localização estão corretos? (s/N): " confirm
    
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        log "Operação cancelada pelo usuário"
        exit 0
    fi
    
    echo ""
}

# ============================================================
# DOWNLOAD DO ICLOUD
# ============================================================

download_from_icloud() {
    log "=========================================="
    log "ETAPA 1: DOWNLOAD DO ICLOUD"
    log "=========================================="
    
    if [ -z "${ICLOUD_USERNAME:-}" ]; then
        read -p "Digite seu email do iCloud: " ICLOUD_USERNAME
    fi
    
    log "Iniciando download para: ${DOWNLOAD_DIR}"
    
    # Usar icloudpd com opções macOS otimizadas
    icloudpd \
        --username "${ICLOUD_USERNAME}" \
        --directory "${DOWNLOAD_DIR}" \
        --keep-unicode-filenames \
        --recent 0 \
        --skip-live-photos \
        --auto-delete \
        --download-everything || {
        error "Erro no download do iCloud"
        return 1
    }
    
    success "Download concluído"
    
    # Contar arquivos
    local file_count=$(find "${DOWNLOAD_DIR}" -type f | wc -l)
    log "Total de arquivos baixados: ${file_count}"
}

# ============================================================
# GERAR HASHES
# ============================================================

generate_file_hashes() {
    log "=========================================="
    log "ETAPA 2: GERANDO HASHES DE ARQUIVOS"
    log "=========================================="
    
    local hash_file="${BACKUP_ROOT}/temp/current_hashes.txt"
    > "${hash_file}"
    
    log "Calculando SHA256 para todos os arquivos..."
    
    # Usar shasum no macOS se sha256sum não disponível
    local hash_cmd="sha256sum"
    if ! command -v sha256sum &> /dev/null; then
        hash_cmd="shasum -a 256"
    fi
    
    find "${DOWNLOAD_DIR}" -type f ! -name ".*" | while read -r file; do
        local hash=$($hash_cmd "$file" | awk '{print $1}')
        echo "${hash}  $file" >> "${hash_file}"
    done
    
    success "Hashes gerados: ${hash_file}"
}

# ============================================================
# DETECTAR DUPLICATAS
# ============================================================

detect_duplicates() {
    log "=========================================="
    log "ETAPA 3: DETECTANDO ARQUIVOS DUPLICADOS"
    log "=========================================="
    
    local hash_file="${BACKUP_ROOT}/temp/current_hashes.txt"
    local duplicates_report="${BACKUP_ROOT}/reports/duplicates_$(date +%Y-%m-%d_%H-%M-%S).txt"
    
    python3 << 'PYTHON_EOF'
import sys
from collections import defaultdict
from pathlib import Path

hash_file = sys.argv[1]
duplicates_report = sys.argv[2]

hash_dict = defaultdict(list)

# Ler hashes
with open(hash_file, 'r') as f:
    for line in f:
        parts = line.strip().rsplit('  ', 1)
        if len(parts) == 2:
            hash_val, filepath = parts
            hash_dict[hash_val].append(filepath)

# Encontrar duplicatas
duplicates = {h: files for h, files in hash_dict.items() if len(files) > 1}

with open(duplicates_report, 'w') as report:
    report.write(f"{'='*80}\n")
    report.write(f"RELATÓRIO DE ARQUIVOS DUPLICADOS\n")
    report.write(f"{'='*80}\n\n")
    
    if duplicates:
        report.write(f"Total de grupos duplicados: {len(duplicates)}\n")
        report.write(f"Total de arquivos duplicados: {sum(len(f)-1 for f in duplicates.values())}\n\n")
        
        for idx, (hash_val, files) in enumerate(duplicates.items(), 1):
            report.write(f"\n[Grupo {idx}] SHA256: {hash_val}\n")
            report.write(f"Arquivos ({len(files)}):\n")
            for filepath in files:
                report.write(f"  → {filepath}\n")
    else:
        report.write("Nenhum arquivo duplicado encontrado! ✓\n")

print(f"Relatório salvo em: {duplicates_report}")
PYTHON_EOF
    
    python3 - "$hash_file" "$duplicates_report"
    
    if [ -f "${duplicates_report}" ]; then
        cat "${duplicates_report}" | tee -a "${LOG_FILE}"
        success "Análise de duplicatas concluída"
    fi
}

# ============================================================
# VERIFICAR INTEGRIDADE
# ============================================================

verify_integrity() {
    log "=========================================="
    log "ETAPA 4: VERIFICANDO INTEGRIDADE"
    log "=========================================="
    
    local hash_file="${BACKUP_ROOT}/temp/current_hashes.txt"
    local verification_report="${BACKUP_ROOT}/reports/verification_$(date +%Y-%m-%d_%H-%M-%S).txt"
    
    log "Verificando integridade de todos os arquivos..."
    
    # Usar shasum em macOS se necessário
    local hash_cmd="sha256sum"
    if ! command -v sha256sum &> /dev/null; then
        # Converter formato para shasum
        sed 's/^//' "$hash_file" > "${hash_file}.tmp"
        hash_cmd="shasum -a 256"
    fi
    
    $hash_cmd -c "${hash_file}" > "${verification_report}" 2>&1 || true
    
    local total=$(wc -l < "${hash_file}")
    local failed=$(grep -c "FAILED" "${verification_report}" || echo 0)
    
    if [ "$failed" -eq 0 ]; then
        success "Integridade verificada: ${total} arquivos OK"
    else
        warning "Integridade: ${failed} arquivos com falha"
    fi
}

# ============================================================
# GERAR SUMÁRIO
# ============================================================

generate_summary() {
    log "=========================================="
    log "ETAPA 5: GERANDO RELATÓRIO FINAL"
    log "=========================================="
    
    > "${REPORT_FILE}"
    
    cat >> "${REPORT_FILE}" << EOF
╔════════════════════════════════════════════════════════════════╗
║        RELATÓRIO FINAL DE BACKUP DO ICLOUD                    ║
╚════════════════════════════════════════════════════════════════╝

📅 DATA/HORA: $(date '+%Y-%m-%d %H:%M:%S')
📁 VOLUME: $(basename "$BACKUP_VOLUME")
📂 DIRETÓRIO: ${DOWNLOAD_DIR}

ESTATÍSTICAS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    # Contar arquivos por tipo
    echo "Quantidade de arquivos: $(find "${DOWNLOAD_DIR}" -type f | wc -l)" >> "${REPORT_FILE}"
    echo "Tamanho total: $(du -sh "${DOWNLOAD_DIR}" | cut -f1)" >> "${REPORT_FILE}"
    
    echo -e "\nTIPOS DE ARQUIVO:" >> "${REPORT_FILE}"
    find "${DOWNLOAD_DIR}" -type f -exec basename {} \; | sed 's/.*\.//' | sort | uniq -c | sort -rn >> "${REPORT_FILE}"
    
    cat >> "${REPORT_FILE}" << EOF

PRÓXIMOS PASSOS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. ✓ COMPLETADO: Download de todas as mídias do iCloud
2. ✓ COMPLETADO: Verificação de duplicatas
3. ✓ COMPLETADO: Verificação de integridade

PRÓXIMAS AÇÕES:
→ Revisar o diretório: ${DOWNLOAD_DIR}
→ Confirmar que todos os arquivos necessários foram baixados
→ Executar script de limpeza apenas APÓS confirmar tudo

AVISOS IMPORTANTES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  Não execute a limpeza automática até verificar manualmente
⚠️  Mantenha este backup como referência antes de deletar arquivos
⚠️  Considere fazer backup em outro disco como segurança extra

ARQUIVO DE LOG:
${LOG_FILE}

EOF

    cat "${REPORT_FILE}"
    success "Relatório salvo em: ${REPORT_FILE}"
}

# ============================================================
# ABRIR PASTA NO FINDER
# ============================================================

open_in_finder() {
    log "Abrindo pasta no Finder..."
    open "${DOWNLOAD_DIR}"
}

# ============================================================
# MAIN
# ============================================================

main() {
    clear
    
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║   🍎 BACKUP ICLOUD - VERSÃO MACOS COM SUPORTE A VOLUMES      ║
║                                                               ║
║   Backup Automatizado + Detecção de Duplicatas               ║
╚═══════════════════════════════════════════════════════════════╝

EOF

    log "Iniciando fluxo de backup..."
    
    create_structure
    show_volume_info
    check_requirements
    confirm_backup
    
    # Executar etapas
    download_from_icloud || exit 1
    generate_file_hashes || exit 1
    detect_duplicates || exit 1
    verify_integrity || exit 1
    generate_summary || exit 1
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ BACKUP COMPLETADO COM SUCESSO!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Próximas ações:"
    echo "  1. Revisar arquivos no Finder (abrindo...)"
    echo "  2. Analisar duplicatas: python3 duplicate_detector.py $DOWNLOAD_DIR"
    echo "  3. Backup em disco externo: rsync -av $BACKUP_ROOT /Volumes/BackupDisk/"
    echo "  4. Limpeza segura: ./safe_cleanup.sh"
    echo ""
    
    # Abrir pasta
    read -p "Abrir pasta no Finder? (s/N): " open_finder
    if [[ "$open_finder" == "s" || "$open_finder" == "S" ]]; then
        open_in_finder
    fi
}

# Executar
main "$@"
