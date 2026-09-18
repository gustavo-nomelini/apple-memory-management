#!/bin/bash

################################################################################
# MONITOR DE BACKUP ICLOUD - VERSÃO CORRIGIDA
# Monitora progresso do backup em tempo real
################################################################################

set -uo pipefail

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════
# CONFIGURAÇÃO
# ═══════════════════════════════════════════════════════════════

# Carregar configuração se existir
if [ -f "$HOME/.icloudpd_volume_config" ]; then
    source "$HOME/.icloudpd_volume_config"
fi

# Valores padrão
BACKUP_VOLUME="${BACKUP_VOLUME:-$HOME}"
BACKUP_ROOT="${BACKUP_ROOT:-$BACKUP_VOLUME/icloud_backups}"
DOWNLOAD_DIR="${BACKUP_ROOT}/downloads"

# ═══════════════════════════════════════════════════════════════
# FUNÇÕES
# ═══════════════════════════════════════════════════════════════

format_bytes() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        printf "%.2f GB" "$(echo "scale=2; $bytes / 1073741824" | bc)"
    fi
}

format_bytes_precise() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        printf "%.2f B" "$bytes"
    elif [ "$bytes" -lt 1048576 ]; then
        printf "%.2f KB" "$(echo "scale=2; $bytes / 1024" | bc)"
    elif [ "$bytes" -lt 1073741824 ]; then
        printf "%.2f MB" "$(echo "scale=2; $bytes / 1048576" | bc)"
    else
        printf "%.2f GB" "$(echo "scale=2; $bytes / 1073741824" | bc)"
    fi
}

get_elapsed_time() {
    local start=$1
    local elapsed=$(($(date +%s) - start))
    
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))
    
    printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
}

get_speed() {
    local bytes=$1
    local seconds=$2
    
    if [ $seconds -eq 0 ]; then
        echo "0 MB/s"
        return
    fi
    
    local mb_per_sec=$(echo "scale=2; ($bytes / 1048576) / $seconds" | bc)
    echo "${mb_per_sec} MB/s"
}

show_header() {
    clear
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║  📊 MONITOR DE BACKUP ICLOUD EM TEMPO REAL                   ║
╚═══════════════════════════════════════════════════════════════╝

EOF
}

show_volume_info() {
    echo -e "${CYAN}📁 VOLUME DE BACKUP${NC}"
    echo "─────────────────────────────────────────────────────"
    
    if [ ! -d "$BACKUP_VOLUME" ]; then
        echo -e "${RED}⚠️  Volume não encontrado: $BACKUP_VOLUME${NC}"
        return
    fi
    
    local volume_name=$(basename "$BACKUP_VOLUME")
    local total=$(df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $2}' || echo "?")
    local used=$(df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $3}' || echo "?")
    local available=$(df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $4}' || echo "?")
    
    echo "Volume: ${CYAN}${volume_name}${NC}"
    echo "Total: $total | Usado: $used | Disponível: $available"
    echo ""
}

show_statistics() {
    echo -e "${CYAN}📊 ESTATÍSTICAS${NC}"
    echo "─────────────────────────────────────────────────────"
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        echo -e "${YELLOW}⚠️  Pasta de download não encontrada${NC}"
        echo "   $DOWNLOAD_DIR"
        echo ""
        return
    fi
    
    # Contar arquivos
    local file_count=$(find "$DOWNLOAD_DIR" -type f 2>/dev/null | wc -l)
    local dir_count=$(find "$DOWNLOAD_DIR" -type d 2>/dev/null | wc -l)
    local total_size=$(du -sb "$DOWNLOAD_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
    
    echo "Arquivos: ${GREEN}${file_count}${NC}"
    echo "Diretórios: ${GREEN}${dir_count}${NC}"
    echo "Tamanho Total: ${GREEN}$(format_bytes_precise $total_size)${NC}"
    echo ""
}

show_recent_files() {
    echo -e "${CYAN}📄 ARQUIVOS RECENTES${NC}"
    echo "─────────────────────────────────────────────────────"
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        return
    fi
    
    local count=$(find "$DOWNLOAD_DIR" -type f -printf '%T@ %s %p\n' 2>/dev/null | wc -l)
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}Nenhum arquivo ainda${NC}"
        echo ""
        return
    fi
    
    find "$DOWNLOAD_DIR" -type f -printf '%T@ %s %p\n' 2>/dev/null | \
        sort -rn | head -10 | while read -r timestamp size path; do
        
        # Converter timestamp
        local date=$(date -r "${timestamp%.*}" '+%H:%M:%S' 2>/dev/null || echo "??:??:??")
        local size_formatted=$(format_bytes "$size")
        local filename=$(basename "$path")
        
        printf "  ${GREEN}%s${NC} | ${YELLOW}%8s${NC} | %s\n" "$date" "$size_formatted" "$filename"
    done
    
    echo ""
}

show_file_types() {
    echo -e "${CYAN}🎨 TIPOS DE ARQUIVO${NC}"
    echo "─────────────────────────────────────────────────────"
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        return
    fi
    
    local count=$(find "$DOWNLOAD_DIR" -type f 2>/dev/null | wc -l)
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}Nenhum arquivo${NC}"
        echo ""
        return
    fi
    
    find "$DOWNLOAD_DIR" -type f 2>/dev/null | \
        sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10 | \
        while read -r count ext; do
            printf "  ${MAGENTA}%-8s${NC} %3d arquivos\n" "$ext" "$count"
        done
    
    echo ""
}

monitor_progress() {
    local start_time=$(date +%s)
    local last_size=0
    local last_time=$start_time
    
    while true; do
        show_header
        show_volume_info
        
        if [ ! -d "$DOWNLOAD_DIR" ]; then
            echo -e "${YELLOW}⚠️  Aguardando início do backup...${NC}"
            sleep 3
            continue
        fi
        
        local current_time=$(date +%s)
        local current_size=$(du -sb "$DOWNLOAD_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
        local time_diff=$((current_time - last_time))
        local size_diff=$((current_size - last_size))
        
        # Calcular velocidade
        local speed_bytes=0
        if [ $time_diff -gt 0 ]; then
            speed_bytes=$((size_diff / time_diff))
        fi
        
        local elapsed=$(get_elapsed_time "$start_time")
        local speed=$(get_speed "$current_size" "$((current_time - start_time))")
        
        show_statistics
        
        # Barra de progresso (simulada com tempo decorrido)
        echo -e "${CYAN}⏱️  TEMPO E VELOCIDADE${NC}"
        echo "─────────────────────────────────────────────────────"
        echo "Tempo decorrido: ${YELLOW}${elapsed}${NC}"
        echo "Velocidade média: ${YELLOW}${speed}${NC}"
        echo "Tamanho atual: ${GREEN}$(format_bytes_precise $current_size)${NC}"
        echo ""
        
        show_recent_files
        show_file_types
        
        # Indicador de atividade
        if [ $size_diff -gt 0 ]; then
            echo -e "${GREEN}✓ Transferência ativa ($(format_bytes $size_diff)/s)${NC}"
        else
            echo -e "${YELLOW}⊙ Aguardando dados...${NC}"
        fi
        
        echo ""
        echo -e "${CYAN}Atualizando em 3 segundos... (Ctrl+C para sair)${NC}"
        echo ""
        
        last_size=$current_size
        last_time=$current_time
        
        sleep 3
    done
}

show_summary_mode() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    SUMÁRIO DE BACKUP${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        echo -e "${RED}Nenhum backup encontrado${NC}"
        echo "Esperando: $DOWNLOAD_DIR"
        return
    fi
    
    show_statistics
    
    echo -e "${CYAN}📋 ÚLTIMOS 20 ARQUIVOS${NC}"
    echo "─────────────────────────────────────────────────────"
    
    find "$DOWNLOAD_DIR" -type f -printf '%T@ %s %p\n' 2>/dev/null | \
        sort -rn | head -20 | while read -r timestamp size path; do
        
        local date=$(date -r "${timestamp%.*}" '+%Y-%m-%d %H:%M' 2>/dev/null)
        local size_formatted=$(format_bytes "$size")
        local filename=$(basename "$path")
        
        printf "%-16s | %8s | %s\n" "$date" "$size_formatted" "$filename"
    done
    
    echo ""
    echo -e "${CYAN}📊 DISTRIBUIÇÃO DE TIPOS${NC}"
    echo "─────────────────────────────────────────────────────"
    
    show_file_types
    
    echo -e "${CYAN}📁 DIRETÓRIOS PRINCIPAIS${NC}"
    echo "─────────────────────────────────────────────────────"
    
    du -sh "$DOWNLOAD_DIR"/*/ 2>/dev/null | sort -rh | head -10 | \
        while read -r size dir; do
            printf "%-8s | %s\n" "$size" "$(basename "$dir")"
        done
    
    echo ""
}

validate_files() {
    echo ""
    echo -e "${CYAN}🔍 VALIDANDO INTEGRIDADE${NC}"
    echo "─────────────────────────────────────────────────────"
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        echo -e "${RED}Diretório não encontrado${NC}"
        return
    fi
    
    local total=$(find "$DOWNLOAD_DIR" -type f 2>/dev/null | wc -l)
    local count=0
    local errors=0
    
    find "$DOWNLOAD_DIR" -type f 2>/dev/null | while read -r file; do
        count=$((count + 1))
        
        if [ ! -r "$file" ]; then
            echo -e "${RED}✗ Erro de acesso: $file${NC}"
            errors=$((errors + 1))
        fi
        
        if [ $((count % 100)) -eq 0 ]; then
            echo -ne "\rValidados: $count/$total"
        fi
    done
    
    echo ""
    echo -e "${GREEN}✓ Validação concluída${NC}"
}

show_menu() {
    cat << 'EOF'

Opções:
  1) Monitorar em tempo real
  2) Ver sumário
  3) Validar integridade
  4) Sair

EOF
    
    read -p "Opção: " choice
    
    case $choice in
        1) monitor_progress;;
        2) show_summary_mode;;
        3) validate_files;;
        4) exit 0;;
        *) echo "Opção inválida";;
    esac
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

main() {
    if [ $# -eq 0 ]; then
        monitor_progress
    else
        case "$1" in
            --summary) show_summary_mode;;
            --validate) validate_files;;
            --help) cat << 'EOF'
Uso: backup_monitor.sh [OPÇÃO]

Opções:
  (sem opção)  Monitorar em tempo real
  --summary    Mostrar sumário
  --validate   Validar integridade
  --help       Mostrar esta ajuda

Exemplos:
  ./backup_monitor.sh                    # Tempo real
  ./backup_monitor.sh --summary          # Sumário
  BACKUP_ROOT=/Volumes/disco ./backup_monitor.sh

EOF
            ;;
            *) monitor_progress;;
        esac
    fi
}

main "$@"
