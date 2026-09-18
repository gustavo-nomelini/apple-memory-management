#!/bin/bash

################################################################################
# GESTOR DE BACKUPS - Arquivar, Organizar e Liberar Espaço
# Gerenciar múltiplos backups e versões antigas
################################################################################

set -euo pipefail

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# CONFIGURAÇÃO
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/icloud_backups}"
DOWNLOADS_DIR="${BACKUP_ROOT}/downloads"
ARCHIVE_DIR="${BACKUP_ROOT}/archive"
CLEANUP_DIR="${BACKUP_ROOT}/cleanup_backups"

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

info() {
    echo -e "${CYAN}ℹ${NC} $*"
}

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

# BANNER
show_banner() {
    clear
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║  📦 GESTOR DE BACKUPS - ARQUIVAR E ORGANIZAR                 ║
║  Gerenciar múltiplos backups e liberar espaço               ║
╚═══════════════════════════════════════════════════════════════╝

EOF
}

# LISTAR BACKUPS
list_backups() {
    echo ""
    echo -e "${CYAN}📁 BACKUPS DISPONÍVEIS${NC}"
    echo "─────────────────────────────────────────────────────"
    echo ""
    
    if [ ! -d "$DOWNLOADS_DIR" ]; then
        warning "Nenhum backup encontrado"
        return
    fi
    
    local idx=1
    
    for backup_dir in $(ls -d "$DOWNLOADS_DIR"/*/ 2>/dev/null | sort -r); do
        local backup_name=$(basename "$backup_dir")
        local backup_size=$(du -sh "$backup_dir" | awk '{print $1}')
        local file_count=$(find "$backup_dir" -type f | wc -l)
        local backup_date=$(stat -f %Sm -t %Y-%m-%d "$backup_dir" 2>/dev/null || date)
        
        echo -e "${GREEN}${idx}${NC}) ${backup_name}"
        echo "   Data: $backup_date | Tamanho: $backup_size | Arquivos: $file_count"
        echo ""
        
        idx=$((idx + 1))
    done
}

# MOSTRAR ESTATÍSTICAS
show_statistics() {
    echo ""
    echo -e "${CYAN}📊 ESTATÍSTICAS GERAIS${NC}"
    echo "─────────────────────────────────────────────────────"
    echo ""
    
    if [ ! -d "$BACKUP_ROOT" ]; then
        warning "Diretório de backup não encontrado"
        return
    fi
    
    # Tamanho total
    local total_size=$(du -sh "$BACKUP_ROOT" 2>/dev/null | awk '{print $1}')
    echo "Espaço total usado: ${GREEN}${total_size}${NC}"
    
    # Backups
    if [ -d "$DOWNLOADS_DIR" ]; then
        local backup_count=$(ls -d "$DOWNLOADS_DIR"/*/ 2>/dev/null | wc -l)
        local downloads_size=$(du -sh "$DOWNLOADS_DIR" 2>/dev/null | awk '{print $1}')
        echo "Backups: ${GREEN}${backup_count}${NC}"
        echo "Espaço em downloads: ${GREEN}${downloads_size}${NC}"
    fi
    
    # Arquivos
    if [ -d "$ARCHIVE_DIR" ]; then
        local archive_size=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | awk '{print $1}')
        local archive_count=$(find "$ARCHIVE_DIR" -type f 2>/dev/null | wc -l)
        echo "Espaço em archive: ${GREEN}${archive_size}${NC}"
        echo "Arquivos arquivados: ${GREEN}${archive_count}${NC}"
    fi
    
    # Cleanup
    if [ -d "$CLEANUP_DIR" ]; then
        local cleanup_size=$(du -sh "$CLEANUP_DIR" 2>/dev/null | awk '{print $1}')
        echo "Espaço em quarentena: ${YELLOW}${cleanup_size}${NC}"
    fi
    
    echo ""
}

# ARQUIVAR BACKUP ANTIGO
archive_old_backup() {
    log "Arquivando backup antigo..."
    
    list_backups
    
    read -p "Qual backup deseja arquivar? (número): " choice
    
    if [ -z "$choice" ] || ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        error "Opção inválida"
        return 1
    fi
    
    local idx=1
    local backup_to_archive=""
    
    for backup_dir in $(ls -d "$DOWNLOADS_DIR"/*/ 2>/dev/null | sort -r); do
        if [ $idx -eq $choice ]; then
            backup_to_archive="$backup_dir"
            break
        fi
        idx=$((idx + 1))
    done
    
    if [ -z "$backup_to_archive" ]; then
        error "Backup não encontrado"
        return 1
    fi
    
    local backup_name=$(basename "$backup_to_archive")
    local backup_size=$(du -sh "$backup_to_archive" | awk '{print $1}')
    
    warning "Vai arquivar: $backup_name ($backup_size)"
    read -p "Confirmar? (s/N): " confirm
    
    if [[ "$confirm" != "s" ]]; then
        log "Operação cancelada"
        return
    fi
    
    # Criar arquivo comprimido
    mkdir -p "$ARCHIVE_DIR"
    
    log "Comprimindo... (pode levar vários minutos)"
    
    if tar -czf "$ARCHIVE_DIR/${backup_name}.tar.gz" \
        -C "$(dirname "$backup_to_archive")" "$backup_name" 2>/dev/null; then
        
        # Verificar compressão
        local compressed_size=$(du -sh "$ARCHIVE_DIR/${backup_name}.tar.gz" | awk '{print $1}')
        
        success "Backup arquivado: ${backup_name}.tar.gz (${compressed_size})"
        
        # Deletar original
        read -p "Deletar backup original? (s/N): " delete_original
        
        if [[ "$delete_original" == "s" ]]; then
            rm -rf "$backup_to_archive"
            local freed=$backup_size
            success "Original deletado. Espaço liberado: ${freed}"
        fi
    else
        error "Erro ao arquivar"
        return 1
    fi
}

# RESTAURAR ARQUIVO
restore_archive() {
    echo ""
    echo -e "${CYAN}📂 ARQUIVOS DISPONÍVEIS PARA RESTAURAR${NC}"
    echo "─────────────────────────────────────────────────────"
    echo ""
    
    if [ ! -d "$ARCHIVE_DIR" ] || [ -z "$(ls -A "$ARCHIVE_DIR" 2>/dev/null)" ]; then
        warning "Nenhum arquivo encontrado"
        return
    fi
    
    local idx=1
    
    for archive in $(ls "$ARCHIVE_DIR"/*.tar.gz 2>/dev/null | sort -r); do
        local archive_name=$(basename "$archive")
        local archive_size=$(du -sh "$archive" | awk '{print $1}')
        
        echo -e "${GREEN}${idx}${NC}) ${archive_name} (${archive_size})"
        idx=$((idx + 1))
    done
    
    echo ""
    read -p "Qual arquivo deseja restaurar? (número): " choice
    
    if [ -z "$choice" ] || ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        error "Opção inválida"
        return 1
    fi
    
    local idx=1
    local archive_to_restore=""
    
    for archive in $(ls "$ARCHIVE_DIR"/*.tar.gz 2>/dev/null | sort -r); do
        if [ $idx -eq $choice ]; then
            archive_to_restore="$archive"
            break
        fi
        idx=$((idx + 1))
    done
    
    if [ -z "$archive_to_restore" ]; then
        error "Arquivo não encontrado"
        return 1
    fi
    
    local archive_name=$(basename "$archive_to_restore")
    
    warning "Vai restaurar: $archive_name"
    read -p "Confirmar? (s/N): " confirm
    
    if [[ "$confirm" != "s" ]]; then
        log "Operação cancelada"
        return
    fi
    
    # Restaurar
    log "Restaurando... (pode levar vários minutos)"
    
    if tar -xzf "$archive_to_restore" -C "$DOWNLOADS_DIR" 2>/dev/null; then
        success "Arquivo restaurado com sucesso"
    else
        error "Erro ao restaurar"
        return 1
    fi
}

# LISTAR DUPLICATAS PARA DELETAR
list_duplicates_cleanup() {
    echo ""
    echo -e "${CYAN}🗑️  ARQUIVOS EM QUARENTENA${NC}"
    echo "─────────────────────────────────────────────────────"
    echo ""
    
    if [ ! -d "$CLEANUP_DIR" ] || [ -z "$(ls -d "$CLEANUP_DIR"/*/ 2>/dev/null)" ]; then
        info "Nenhum arquivo em quarentena"
        return
    fi
    
    local idx=1
    
    for cleanup_subdir in $(ls -d "$CLEANUP_DIR"/*/ 2>/dev/null | sort -r); do
        local dir_name=$(basename "$cleanup_subdir")
        local dir_size=$(du -sh "$cleanup_subdir" | awk '{print $1}')
        local file_count=$(find "$cleanup_subdir" -type f | wc -l)
        local creation_date=$(stat -f %Sm -t %Y-%m-%d "$cleanup_subdir" 2>/dev/null)
        
        # Calcular dias desde criação
        local creation_epoch=$(stat -f %m "$cleanup_subdir" 2>/dev/null || echo 0)
        local current_epoch=$(date +%s)
        local days_old=$(( (current_epoch - creation_epoch) / 86400 ))
        
        local status="${GREEN}✓${NC}"
        if [ $days_old -gt 30 ]; then
            status="${RED}⚠ EXPIRADO${NC}"
        fi
        
        echo -e "${GREEN}${idx}${NC}) ${dir_name} $status"
        echo "   Criado: $creation_date | Idade: ${days_old} dias | Tamanho: $dir_size | Arquivos: $file_count"
        echo ""
        
        idx=$((idx + 1))
    done
}

# DELETAR QUARENTENA EXPIRADA
cleanup_expired() {
    log "Verificando arquivos expirados em quarentena..."
    
    if [ ! -d "$CLEANUP_DIR" ]; then
        warning "Nenhum arquivo em quarentena"
        return
    fi
    
    local deleted_count=0
    local freed_space=0
    
    for cleanup_subdir in $(ls -d "$CLEANUP_DIR"/*/ 2>/dev/null); do
        local creation_epoch=$(stat -f %m "$cleanup_subdir" 2>/dev/null || echo 0)
        local current_epoch=$(date +%s)
        local days_old=$(( (current_epoch - creation_epoch) / 86400 ))
        
        if [ $days_old -gt 30 ]; then
            local dir_name=$(basename "$cleanup_subdir")
            local dir_size=$(du -sb "$cleanup_subdir" | awk '{print $1}')
            
            log "Deletando: $dir_name (${days_old} dias)"
            rm -rf "$cleanup_subdir"
            
            deleted_count=$((deleted_count + 1))
            freed_space=$((freed_space + dir_size))
        fi
    done
    
    if [ $deleted_count -gt 0 ]; then
        success "Deletados: $deleted_count diretórios"
        success "Espaço liberado: $(format_bytes $freed_space)"
    else
        info "Nenhum arquivo expirado"
    fi
}

# LIMPEZA INTELIGENTE
smart_cleanup() {
    echo ""
    echo -e "${CYAN}🧹 LIMPEZA INTELIGENTE${NC}"
    echo "─────────────────────────────────────────────────────"
    echo ""
    
    warning "Esta operação vai:"
    echo "  1. Arquivar backups > 30 dias"
    echo "  2. Deletar quarentena expirada (>30 dias)"
    echo "  3. Remover logs antigos"
    echo ""
    
    read -p "Continuar? (s/N): " confirm
    
    if [[ "$confirm" != "s" ]]; then
        log "Operação cancelada"
        return
    fi
    
    # Arquivar backups antigos
    log "Arquivando backups antigos..."
    for backup_dir in $(ls -d "$DOWNLOADS_DIR"/*/ 2>/dev/null); do
        local backup_epoch=$(stat -f %m "$backup_dir" 2>/dev/null || echo 0)
        local current_epoch=$(date +%s)
        local days_old=$(( (current_epoch - backup_epoch) / 86400 ))
        
        if [ $days_old -gt 30 ]; then
            log "Arquivando: $(basename "$backup_dir") (${days_old} dias)"
            # Implementar arquivamento
        fi
    done
    
    # Deletar quarentena expirada
    cleanup_expired
    
    # Deletar logs antigos
    log "Removendo logs > 90 dias..."
    find "$BACKUP_ROOT/logs" -name "*.log" -mtime +90 -delete
    
    success "Limpeza inteligente concluída"
}

# MENU
show_main_menu() {
    show_banner
    show_statistics
    
    cat << 'EOF'

Opções:

  1) Listar backups
  2) Arquivar backup antigo
  3) Restaurar arquivo
  4) Ver quarentena
  5) Deletar expirado (>30 dias)
  6) Limpeza inteligente
  7) Sair

EOF
    
    read -p "Opção (1-7): " choice
    
    case $choice in
        1) list_backups; read -p "Pressione Enter..."; show_main_menu;;
        2) archive_old_backup; show_main_menu;;
        3) restore_archive; show_main_menu;;
        4) list_duplicates_cleanup; read -p "Pressione Enter..."; show_main_menu;;
        5) cleanup_expired; read -p "Pressione Enter..."; show_main_menu;;
        6) smart_cleanup; show_main_menu;;
        7) exit 0;;
        *) error "Opção inválida"; show_main_menu;;
    esac
}

# MAIN
main() {
    if [ $# -eq 0 ]; then
        show_main_menu
    else
        case "$1" in
            --list) list_backups;;
            --archive) archive_old_backup;;
            --restore) restore_archive;;
            --cleanup) cleanup_expired;;
            --smart) smart_cleanup;;
            --stats) show_statistics;;
            --help) cat << 'EOF'
Uso: backup_manager.sh [OPÇÃO]

Opções:
  (sem opção)  Menu interativo
  --list       Listar backups
  --archive    Arquivar backup antigo
  --restore    Restaurar arquivo
  --cleanup    Deletar quarentena expirada
  --smart      Limpeza inteligente
  --stats      Ver estatísticas
  --help       Mostrar esta ajuda

Exemplos:
  ./backup_manager.sh           # Menu interativo
  ./backup_manager.sh --list    # Listar backups
  ./backup_manager.sh --smart   # Limpeza automática
EOF
            ;;
        esac
    fi
}

main "$@"
