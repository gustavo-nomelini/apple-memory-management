#!/bin/bash

################################################################################
# MONITOR DE BACKUP EM TEMPO REAL
# Acompanhar progresso com estatísticas detalhadas
################################################################################

set -euo pipefail

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# CONFIGURAÇÃO
BACKUP_VOLUME="${BACKUP_VOLUME:-$HOME}"
BACKUP_ROOT="${BACKUP_ROOT:-$BACKUP_VOLUME/icloud_backups}"
DOWNLOAD_DIR="${BACKUP_ROOT}/downloads"
UPDATE_INTERVAL=${1:-3}  # Segundos entre updates

# HISTÓRICO
declare -a FILE_HISTORY
declare -a SIZE_HISTORY
declare -a TIME_HISTORY

# FUNÇÕES
format_bytes() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

format_bytes_precise() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        printf "%.2f B" "$bytes"
    elif [ $bytes -lt 1048576 ]; then
        printf "%.2f KB" "$(echo "scale=2; $bytes / 1024" | bc)"
    elif [ $bytes -lt 1073741824 ]; then
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

get_eta() {
    local bytes_downloaded=$1
    local speed_bytes=$2
    local target_bytes=$3
    
    if [ $speed_bytes -eq 0 ]; then
        echo "Calculando..."
        return
    fi
    
    local bytes_remaining=$((target_bytes - bytes_downloaded))
    local seconds_remaining=$((bytes_remaining / speed_bytes))
    
    local hours=$((seconds_remaining / 3600))
    local minutes=$(((seconds_remaining % 3600) / 60))
    
    printf "%02d:%02d" "$hours" "$minutes"
}

get_percentage() {
    local current=$1
    local total=$2
    
    if [ $total -eq 0 ]; then
        echo "0"
        return
    fi
    
    echo "$((current * 100 / total))"
}

draw_progress_bar() {
    local percentage=$1
    local width=50
    local filled=$((percentage * width / 100))
    local empty=$((width - filled))
    
    printf "["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "]"
}

# CABEÇALHO
show_header() {
    clear
    
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║  📊 MONITOR DE BACKUP ICLOUD EM TEMPO REAL                   ║
╚═══════════════════════════════════════════════════════════════╝

EOF
}

# INFORMAÇÕES DO VOLUME
show_volume_info() {
    echo -e "${CYAN}📁 VOLUME DE BACKUP${NC}"
    echo "─────────────────────────────────────────────────────"
    
    local volume_name=$(basename "$BACKUP_VOLUME")
    local total=$(df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $2}')
    local used=$(df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $3}')
    local available=$(df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $4}')
    
    echo "Volume: ${MAGENTA}${volume_name}${NC}"
    echo "Total: ${total} | Usado: ${used} | Disponível: ${available}"
    echo ""
}

# ESTATÍSTICAS GERAIS
show_statistics() {
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        echo -e "${YELLOW}⚠  Pasta de download não encontrada${NC}"
        return
    fi
    
    echo -e "${CYAN}📊 ESTATÍSTICAS${NC}"
    echo "─────────────────────────────────────────────────────"
    
    # Contar arquivos
    local file_count=$(find "$DOWNLOAD_DIR" -type f 2>/dev/null | wc -l)
    local dir_count=$(find "$DOWNLOAD_DIR" -type d 2>/dev/null | wc -l)
    local total_size=$(du -sb "$DOWNLOAD_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
    
    echo "Arquivos: ${GREEN}${file_count}${NC}"
    echo "Diretórios: ${GREEN}${dir_count}${NC}"
    echo "Tamanho Total: ${GREEN}$(format_bytes_precise $total_size)${NC}"
    echo ""
}

# ARQUIVOS RECENTES
show_recent_files() {
    echo -e "${CYAN}📄 ARQUIVOS RECENTES${NC}"
    echo "─────────────────────────────────────────────────────"
    
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

# TIPOS DE ARQUIVO
show_file_types() {
    echo -e "${CYAN}🎨 TIPOS DE ARQUIVO${NC}"
    echo "─────────────────────────────────────────────────────"
    
    find "$DOWNLOAD_DIR" -type f 2>/dev/null | \
        sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10 | \
        while read -r count ext; do
            local bar_width=$((count / 5))
            printf "  ${MAGENTA}%-8s${NC} %3d  " "$ext" "$count"
            printf "%${bar_width}s\n" | tr ' ' '█'
        done
    
    echo ""
}

# MONITORAR PROGRESSO
monitor_progress() {
    local start_time=$(date +%s)
    local last_size=0
    local last_time=$start_time
    
    while true; do
        show_header
        show_volume_info
        
        if [ ! -d "$DOWNLOAD_DIR" ]; then
            echo -e "${YELLOW}⚠  Aguardando início do backup...${NC}"
            sleep "$UPDATE_INTERVAL"
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
            echo -e "${GREEN}✓ Transferência ativa (${size_diff} bytes/s)${NC}"
        else
            echo -e "${YELLOW}⊙ Aguardando dados...${NC}"
        fi
        
        last_size=$current_size
        last_time=$current_time
        
        sleep "$UPDATE_INTERVAL"
    done
}

# MODO SUMÁRIO
show_summary_mode() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    SUMÁRIO DE BACKUP${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        echo -e "${RED}Nenhum backup encontrado${NC}"
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

# VALIDAR INTEGRIDADE
validate_files() {
    echo ""
    echo -e "${CYAN}🔍 VALIDANDO INTEGRIDADE${NC}"
    echo "─────────────────────────────────────────────────────"
    
    local total=$(find "$DOWNLOAD_DIR" -type f | wc -l)
    local count=0
    local errors=0
    
    find "$DOWNLOAD_DIR" -type f | while read -r file; do
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
    echo -e "${GREEN}✓ Validação completa${NC}"
}

# MENU
show_menu() {
    cat << 'EOF'

Opções:
  1) Monitorar em tempo real
  2) Ver sumário
  3) Validar integridade
  4) Limpar logs
  5) Sair

EOF
    
    read -p "Opção: " choice
    
    case $choice in
        1) monitor_progress;;
        2) show_summary_mode;;
        3) validate_files;;
        4) rm -rf "$BACKUP_ROOT/logs/"*; echo "Logs limpos";;
        5) exit 0;;
        *) echo "Opção inválida";;
    esac
}

# MAIN
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
  BACKUP_ROOT=/Volumes/disco ./backup_monitor.sh  # Disco customizado
EOF
            ;;
            *) monitor_progress;;
        esac
    fi
}

main "$@"
