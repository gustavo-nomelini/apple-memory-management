#!/bin/bash

################################################################################
# MONITOR DE BACKUP ICLOUD - TEMPO REAL (SEM BUGS)
# Loop contínuo, calcula velocidade, sem variáveis undefined
################################################################################

set -uo pipefail

# CORES (sem variáveis estranhas)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════
# CONFIGURAÇÃO
# ═══════════════════════════════════════════════════════════════

if [ -f "$HOME/.icloudpd_volume_config" ]; then
    source "$HOME/.icloudpd_volume_config"
fi

BACKUP_VOLUME="${BACKUP_VOLUME:-$HOME}"
BACKUP_ROOT="${BACKUP_ROOT:-$BACKUP_VOLUME/icloud_backups}"
DOWNLOAD_DIR="${BACKUP_ROOT}/downloads"

# Variáveis de tempo
START_TIME=$(date +%s)
LAST_SIZE=0
LAST_TIME=$START_TIME

# ═══════════════════════════════════════════════════════════════
# FUNÇÕES SIMPLES (SEM bc, SEM VARIÁVEIS UNDEFINED)
# ═══════════════════════════════════════════════════════════════

format_bytes() {
    local bytes=$1
    
    # Evitar divisão por zero
    if [ "$bytes" -eq 0 ]; then
        echo "0.00 B"
        return
    fi
    
    # Usar awk ao invés de bc
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        awk "BEGIN {printf \"%.2f KB\", $bytes / 1024}"
    elif [ "$bytes" -lt 1073741824 ]; then
        awk "BEGIN {printf \"%.2f MB\", $bytes / 1048576}"
    else
        awk "BEGIN {printf \"%.2f GB\", $bytes / 1073741824}"
    fi
}

get_elapsed() {
    local elapsed=$(($(date +%s) - START_TIME))
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))
    local seconds=$((elapsed % 60))
    printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
}

get_speed() {
    local bytes=$1
    local seconds=$2
    
    if [ $seconds -eq 0 ]; then
        echo "0.00 MB/s"
        return
    fi
    
    # Calcular MB/s com awk
    awk "BEGIN {printf \"%.2f MB/s\", ($bytes / 1048576) / $seconds}"
}

# ═══════════════════════════════════════════════════════════════
# MAIN - MONITOR EM TEMPO REAL
# ═══════════════════════════════════════════════════════════════

monitor_realtime() {
    # Verificar se diretório existe
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        echo ""
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║  📊 MONITOR DE BACKUP ICLOUD                                ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        echo -e "${YELLOW}⚠️  Aguardando início do backup...${NC}"
        echo ""
        echo "Caminho: $DOWNLOAD_DIR"
        echo ""
        echo -e "${CYAN}(Pressione Ctrl+C para sair)${NC}"
        echo ""
        exit 1
    fi
    
    # Loop contínuo
    while true; do
        clear
        
        # ═══════════════════════════════════════════════════════════
        # HEADER
        # ═══════════════════════════════════════════════════════════
        
        echo ""
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║  📊 MONITOR DE BACKUP ICLOUD EM TEMPO REAL                   ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        
        # ═══════════════════════════════════════════════════════════
        # VOLUME INFO
        # ═══════════════════════════════════════════════════════════
        
        echo -e "${CYAN}📁 VOLUME DE BACKUP${NC}"
        echo "─────────────────────────────────────────────────────"
        
        local vol_name=$(basename "$BACKUP_VOLUME")
        local total_space=$(df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $2}' || echo "?")
        local used_space=$(df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $3}' || echo "?")
        local avail_space=$(df -h "$BACKUP_VOLUME" 2>/dev/null | awk 'NR==2 {print $4}' || echo "?")
        
        echo "Volume: ${CYAN}${vol_name}${NC}"
        echo "Total: $total_space | Usado: $used_space | Disponível: $avail_space"
        echo ""
        
        # ═══════════════════════════════════════════════════════════
        # ESTATÍSTICAS
        # ═══════════════════════════════════════════════════════════
        
        local file_count=$(find "$DOWNLOAD_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
        local dir_count=$(find "$DOWNLOAD_DIR" -type d 2>/dev/null | wc -l | tr -d ' ')
        local total_bytes=$(du -sb "$DOWNLOAD_DIR" 2>/dev/null | awk '{print $1}' | tr -d ' ')
        
        if [ -z "$total_bytes" ]; then
            total_bytes=0
        fi
        if [ -z "$file_count" ]; then
            file_count=0
        fi
        if [ -z "$dir_count" ]; then
            dir_count=0
        fi
        
        echo -e "${CYAN}📊 ESTATÍSTICAS${NC}"
        echo "─────────────────────────────────────────────────────"
        echo "Arquivos: ${GREEN}${file_count}${NC}"
        echo "Diretórios: ${GREEN}${dir_count}${NC}"
        echo "Tamanho Total: ${GREEN}$(format_bytes "$total_bytes")${NC}"
        echo ""
        
        # ═══════════════════════════════════════════════════════════
        # TEMPO E VELOCIDADE
        # ═══════════════════════════════════════════════════════════
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - START_TIME))
        local time_diff=$((current_time - LAST_TIME))
        local size_diff=$((total_bytes - LAST_SIZE))
        
        local speed=$(get_speed "$total_bytes" "$elapsed")
        local current_speed=$(get_speed "$size_diff" "$time_diff")
        
        echo -e "${CYAN}⏱️  TEMPO E VELOCIDADE${NC}"
        echo "─────────────────────────────────────────────────────"
        echo "Tempo decorrido: ${YELLOW}$(get_elapsed)${NC}"
        echo "Velocidade média: ${YELLOW}${speed}${NC}"
        echo "Velocidade atual: ${YELLOW}${current_speed}${NC}"
        echo "Tamanho atual: ${GREEN}$(format_bytes "$total_bytes")${NC}"
        echo ""
        
        # ═══════════════════════════════════════════════════════════
        # ÚLTIMOS ARQUIVOS
        # ═══════════════════════════════════════════════════════════
        
        echo -e "${CYAN}📄 ÚLTIMOS ARQUIVOS (últimos 5)${NC}"
        echo "─────────────────────────────────────────────────────"
        
        if [ "$file_count" -eq 0 ]; then
            echo -e "${YELLOW}Aguardando dados...${NC}"
        else
            find "$DOWNLOAD_DIR" -type f -printf '%T@ %s %p\n' 2>/dev/null | \
                sort -rn | head -5 | while read -r timestamp size path; do
                
                local date=$(date -r "${timestamp%.*}" '+%H:%M:%S' 2>/dev/null || echo "??:??:??")
                local size_fmt=$(format_bytes "$size")
                local filename=$(basename "$path")
                
                printf "  ${GREEN}%-10s${NC} | ${YELLOW}%12s${NC} | %s\n" "$date" "$size_fmt" "$filename"
            done
        fi
        
        echo ""
        
        # ═══════════════════════════════════════════════════════════
        # TIPOS DE ARQUIVO
        # ═══════════════════════════════════════════════════════════
        
        echo -e "${CYAN}🎨 TIPOS DE ARQUIVO (top 8)${NC}"
        echo "─────────────────────────────────────────────────────"
        
        if [ "$file_count" -eq 0 ]; then
            echo -e "${YELLOW}Nenhum arquivo${NC}"
        else
            find "$DOWNLOAD_DIR" -type f 2>/dev/null | \
                sed 's/.*\.//' | sort | uniq -c | sort -rn | head -8 | \
                while read -r count ext; do
                    count=$(echo "$count" | tr -d ' ')
                    printf "  %-8s | %4d arquivos\n" "$ext" "$count"
                done
        fi
        
        echo ""
        
        # ═══════════════════════════════════════════════════════════
        # STATUS
        # ═══════════════════════════════════════════════════════════
        
        if [ "$size_diff" -gt 0 ]; then
            echo -e "${GREEN}✓ Transferência ativa (+$(format_bytes "$size_diff")/s)${NC}"
        else
            echo -e "${YELLOW}⊙ Aguardando dados...${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}Atualizando em 2 segundos... (${CYAN}Ctrl+C${BLUE} para sair)${NC}"
        echo ""
        
        # Atualizar variáveis
        LAST_SIZE=$total_bytes
        LAST_TIME=$current_time
        
        # Aguardar
        sleep 2
    done
}

# ═══════════════════════════════════════════════════════════════
# MODO SUMÁRIO (sem loop)
# ═══════════════════════════════════════════════════════════════

show_summary() {
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        echo -e "${RED}Nenhum backup encontrado${NC}"
        exit 1
    fi
    
    clear
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  📊 SUMÁRIO DE BACKUP                                       ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Estatísticas
    local file_count=$(find "$DOWNLOAD_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    local total_bytes=$(du -sb "$DOWNLOAD_DIR" 2>/dev/null | awk '{print $1}' | tr -d ' ')
    
    echo -e "${CYAN}📊 ESTATÍSTICAS${NC}"
    echo "Arquivos: ${GREEN}${file_count}${NC}"
    echo "Tamanho: ${GREEN}$(format_bytes "$total_bytes")${NC}"
    echo ""
    
    # Últimos arquivos
    echo -e "${CYAN}📄 ÚLTIMOS 10 ARQUIVOS${NC}"
    echo "─────────────────────────────────────────────────────"
    
    find "$DOWNLOAD_DIR" -type f -printf '%T@ %s %p\n' 2>/dev/null | \
        sort -rn | head -10 | while read -r timestamp size path; do
        
        local date=$(date -r "${timestamp%.*}" '+%Y-%m-%d %H:%M' 2>/dev/null)
        local size_fmt=$(format_bytes "$size")
        local filename=$(basename "$path")
        
        printf "%-16s | %12s | %s\n" "$date" "$size_fmt" "$filename"
    done
    
    echo ""
    
    # Tipos
    echo -e "${CYAN}🎨 TIPOS DE ARQUIVO${NC}"
    echo "─────────────────────────────────────────────────────"
    
    find "$DOWNLOAD_DIR" -type f 2>/dev/null | \
        sed 's/.*\.//' | sort | uniq -c | sort -rn | head -15 | \
        while read -r count ext; do
            count=$(echo "$count" | tr -d ' ')
            printf "%-8s | %4d arquivos\n" "$ext" "$count"
        done
    
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# ENTRADA
# ═══════════════════════════════════════════════════════════════

case "${1:-}" in
    --summary)
        show_summary
        ;;
    --help)
        cat << 'EOFHELP'
Monitor de Backup do iCloud

Uso:
  ./backup_monitor.sh              # Tempo real (atualiza a cada 2s)
  ./backup_monitor.sh --summary    # Sumário (uma única vez)
  ./backup_monitor.sh --help       # Esta ajuda

Exemplos:
  # Monitorar em tempo real
  ./backup_monitor.sh

  # Ver sumário rápido
  ./backup_monitor.sh --summary

  # Com volume customizado
  BACKUP_ROOT=/Volumes/SSD1TB/icloud_backups ./backup_monitor.sh

EOFHELP
        ;;
    *)
        monitor_realtime
        ;;
esac
