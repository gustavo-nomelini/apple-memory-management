#!/bin/bash

################################################################################
# GESTOR DE VOLUMES PARA BACKUP
# Detecta, lista e gerencia volumes macOS para backup iCloud
################################################################################

set -euo pipefail

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# DETECTAR VOLUMES
detect_volumes() {
    log "Detectando volumes disponíveis..."
    
    # Listar todos os volumes
    local volumes=$(diskutil list | grep -E "^/dev/" | awk '{print $1}' | sort -u)
    
    # Array para armazenar info dos volumes
    declare -a VOLUME_INFO
    local idx=0
    
    while IFS= read -r device; do
        # Obter informações
        local mount_point=$(diskutil info "$device" 2>/dev/null | grep "Mount Point" | awk -F': ' '{print $2}' || echo "N/A")
        
        # Pular volumes do sistema
        if [[ "$mount_point" == "/" || "$mount_point" == "/Volumes/Recovery"* || "$mount_point" == "N/A" ]]; then
            continue
        fi
        
        # Obter tamanho total e disponível
        local volume_name=$(basename "$mount_point" 2>/dev/null || echo "Unknown")
        
        if [ -d "$mount_point" ] && [ "$mount_point" != "/" ]; then
            local total=$(df -h "$mount_point" 2>/dev/null | awk 'NR==2 {print $2}')
            local available=$(df -h "$mount_point" 2>/dev/null | awk 'NR==2 {print $4}')
            local used=$(df -h "$mount_point" 2>/dev/null | awk 'NR==2 {print $3}')
            
            VOLUME_INFO[$idx]="$mount_point|$volume_name|$total|$used|$available"
            idx=$((idx + 1))
        fi
    done <<< "$volumes"
    
    # Também adicionar o volume principal
    if [ ${#VOLUME_INFO[@]} -eq 0 ]; then
        local home_drive=$(df -h ~ | awk 'NR==2 {print $1}')
        local total=$(df -h ~ | awk 'NR==2 {print $2}')
        local available=$(df -h ~ | awk 'NR==2 {print $4}')
        local used=$(df -h ~ | awk 'NR==2 {print $3}')
        VOLUME_INFO[0]="$HOME|Macintosh HD|$total|$used|$available"
    fi
    
    # Retornar array
    printf '%s\n' "${VOLUME_INFO[@]}"
}

# LISTAR VOLUMES FORMATADO
list_volumes() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              VOLUMES DISPONÍVEIS NO MAC                     ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local volumes=$(detect_volumes)
    local idx=1
    local default_idx=1
    
    while IFS='|' read -r mount_point volume_name total used available; do
        local is_internal=0
        
        # Marcar volume do sistema
        if [[ "$mount_point" == "$HOME"* ]] || [[ "$mount_point" == "/Volumes/Macintosh"* ]]; then
            echo -e "${GREEN}${idx}${NC}) ${CYAN}${volume_name}${NC} ${GREEN}(Volume Principal)${NC}"
            is_internal=1
            default_idx=$idx
        else
            echo -e "${GREEN}${idx}${NC}) ${CYAN}${volume_name}${NC}"
        fi
        
        echo "     Caminho: $mount_point"
        echo "     Total: $total | Usado: $used | Disponível: $available"
        echo ""
        
        idx=$((idx + 1))
    done <<< "$volumes"
    
    echo -e "${YELLOW}Recomendação: Use um volume externo (mais rápido e seguro)${NC}"
    echo ""
}

# VERIFICAR ESPAÇO NECESSÁRIO
check_space_required() {
    local target_volume="$1"
    local space_needed="${2:-50}"  # GB padrão: 50GB
    
    log "Verificando espaço disponível em: $target_volume"
    
    # Obter espaço disponível em bytes e converter para GB
    local available_bytes=$(df "$target_volume" 2>/dev/null | awk 'NR==2 {print $4}' | awk '{print $1 * 1024 * 1024}')
    local available_gb=$((available_bytes / 1024 / 1024 / 1024))
    
    echo ""
    echo "Espaço necessário (estimado): ${space_needed} GB"
    echo "Espaço disponível: ${available_gb} GB"
    echo ""
    
    if [ "$available_gb" -lt "$space_needed" ]; then
        warning "Espaço insuficiente! Recomendação: ${space_needed}GB, Disponível: ${available_gb}GB"
        return 1
    fi
    
    success "Espaço suficiente disponível"
    return 0
}

# SELECIONAR VOLUME INTERATIVO
select_volume() {
    local volumes=$(detect_volumes)
    local idx=1
    declare -a volume_paths
    declare -a volume_names
    
    # Preencher arrays
    while IFS='|' read -r mount_point volume_name total used available; do
        volume_paths[$idx]="$mount_point"
        volume_names[$idx]="$volume_name ($total)"
        idx=$((idx + 1))
    done <<< "$volumes"
    
    list_volumes
    
    echo "Qual volume deseja usar para backup? (1-$((idx-1))): "
    read -p "Opção: " choice
    
    if [ -z "${volume_paths[$choice]:-}" ]; then
        error "Opção inválida"
        return 1
    fi
    
    local selected_path="${volume_paths[$choice]}"
    local selected_name="${volume_names[$choice]}"
    
    success "Volume selecionado: $selected_name"
    echo "$selected_path"
}

# CRIAR CONFIG FILE
create_config() {
    local volume_path="$1"
    local config_file="$HOME/.icloudpd_volume_config"
    
    cat > "$config_file" << EOF
# Configuração de Volume para Backup iCloud
# Gerado: $(date)

# Volume principal para backup
BACKUP_VOLUME="$volume_path"

# Criar estrutura em:
BACKUP_ROOT="\${BACKUP_VOLUME}/icloud_backups"

# Diretórios
DOWNLOAD_DIR="\${BACKUP_ROOT}/downloads"
ARCHIVE_DIR="\${BACKUP_ROOT}/archive"
DUPLICATES_DIR="\${BACKUP_ROOT}/duplicates"
LOGS_DIR="\${BACKUP_ROOT}/logs"
REPORTS_DIR="\${BACKUP_ROOT}/reports"

# Espaço monitorado (recalcular quando necessário)
LAST_CHECKED="$(date)"
EOF

    success "Configuração salva em: $config_file"
    cat "$config_file"
}

# VALIDAR ACESSO AO VOLUME
validate_volume_access() {
    local volume_path="$1"
    
    log "Validando acesso ao volume: $volume_path"
    
    if [ ! -d "$volume_path" ]; then
        error "Volume não encontrado ou não acessível"
        return 1
    fi
    
    if [ ! -w "$volume_path" ]; then
        error "Sem permissão de escrita no volume"
        return 1
    fi
    
    success "Acesso validado com sucesso"
    return 0
}

# CRIAR ESTRUTURA NO VOLUME
setup_volume_structure() {
    local volume_path="$1"
    
    log "Criando estrutura de diretórios no volume..."
    
    mkdir -p "$volume_path/icloud_backups"/{downloads,archive,duplicates,logs,reports,temp,cleanup_backups}
    
    # Permissões
    chmod 750 "$volume_path/icloud_backups"
    chmod 755 "$volume_path/icloud_backups"/{downloads,archive,logs,reports}
    chmod 700 "$volume_path/icloud_backups"/{duplicates,temp,cleanup_backups}
    
    success "Estrutura criada em: $volume_path/icloud_backups"
    
    # Listar estrutura
    echo ""
    echo "Estrutura criada:"
    tree -L 2 "$volume_path/icloud_backups" 2>/dev/null || find "$volume_path/icloud_backups" -maxdepth 2 -type d
}

# LISTAR VOLUMES MONTADOS
list_mounted_volumes() {
    echo ""
    echo "📱 Volumes montados no macOS:"
    echo ""
    
    diskutil list | grep -E "^/dev/" | while read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        local info=$(diskutil info "$device" 2>/dev/null | grep "Device / Media Name" | awk -F': ' '{print $2}')
        local mount=$(diskutil info "$device" 2>/dev/null | grep "Mount Point" | awk -F': ' '{print $2}')
        
        if [ ! -z "$mount" ] && [ "$mount" != "/" ]; then
            echo "  $device → $info ($mount)"
        fi
    done
    
    echo ""
}

# MONTAR VOLUME EXTERNO
mount_external_volume() {
    echo ""
    echo "📱 Dispositivos USB/Externos disponíveis:"
    echo ""
    
    # Listar discos não montados
    diskutil list external | grep -E "^/dev/" | while read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        echo "  $device"
    done
    
    echo ""
    read -p "Digite o device (ex: /dev/disk2): " device
    
    if [ -z "$device" ]; then
        error "Device não especificado"
        return 1
    fi
    
    # Tentar montar
    log "Montando $device..."
    
    if diskutil mount "$device" 2>/dev/null; then
        success "Volume montado com sucesso"
        diskutil info "$device" | grep "Mount Point"
    else
        error "Falha ao montar volume"
        return 1
    fi
}

# MENU PRINCIPAL
show_main_menu() {
    clear
    
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║         🔧 GERENCIADOR DE VOLUMES - BACKUP ICLOUD           ║
╚═══════════════════════════════════════════════════════════════╝

O que deseja fazer?

  1) Listar todos os volumes disponíveis
  2) Selecionar volume para backup (interativo)
  3) Montar volume externo USB/Thunderbolt
  4) Validar volume selecionado
  5) Criar estrutura de backup em volume
  6) Ver configuração atual
  7) Sair

EOF

    read -p "Opção (1-7): " choice
    
    case $choice in
        1) list_volumes; read -p "Pressione Enter para voltar..." ; show_main_menu;;
        2) select_volume_interactive;;
        3) mount_external_volume; show_main_menu;;
        4) validate_selected_volume;;
        5) setup_selected_volume;;
        6) show_current_config;;
        7) exit 0;;
        *) error "Opção inválida"; show_main_menu;;
    esac
}

# SELECIONAR VOLUME INTERATIVO
select_volume_interactive() {
    list_volumes
    
    local volumes=$(detect_volumes)
    local idx=1
    declare -a volume_paths
    
    while IFS='|' read -r mount_point volume_name total used available; do
        volume_paths[$idx]="$mount_point"
        idx=$((idx + 1))
    done <<< "$volumes"
    
    read -p "Qual volume deseja usar? (1-$((idx-1))): " choice
    
    if [ -z "${volume_paths[$choice]:-}" ]; then
        error "Opção inválida"
        return 1
    fi
    
    local selected="${volume_paths[$choice]}"
    
    # Validar
    if ! validate_volume_access "$selected"; then
        return 1
    fi
    
    # Verificar espaço
    if ! check_space_required "$selected" 100; then
        warning "Continuar mesmo assim? (s/N):"
        read -p "Opção: " cont
        if [[ "$cont" != "s" ]]; then
            return 1
        fi
    fi
    
    # Criar config
    create_config "$selected"
    
    success "Pronto! Configure BACKUP_ROOT em seus scripts"
    echo ""
    echo "Próximo passo:"
    echo "  export BACKUP_ROOT='$selected/icloud_backups'"
    echo "  ./backup_icloud_workflow.sh"
}

# VALIDAR VOLUME SELECIONADO
validate_selected_volume() {
    if [ ! -f "$HOME/.icloudpd_volume_config" ]; then
        error "Nenhum volume configurado"
        read -p "Pressione Enter..." 
        show_main_menu
        return
    fi
    
    source "$HOME/.icloudpd_volume_config"
    
    echo ""
    log "Validando: $BACKUP_VOLUME"
    
    if validate_volume_access "$BACKUP_VOLUME"; then
        check_space_required "$BACKUP_VOLUME" 100
    fi
    
    read -p "Pressione Enter..." 
    show_main_menu
}

# SETUP VOLUME SELECIONADO
setup_selected_volume() {
    if [ ! -f "$HOME/.icloudpd_volume_config" ]; then
        error "Nenhum volume configurado"
        read -p "Pressione Enter..." 
        show_main_menu
        return
    fi
    
    source "$HOME/.icloudpd_volume_config"
    
    setup_volume_structure "$BACKUP_VOLUME"
    
    read -p "Pressione Enter..." 
    show_main_menu
}

# MOSTRAR CONFIG ATUAL
show_current_config() {
    echo ""
    
    if [ ! -f "$HOME/.icloudpd_volume_config" ]; then
        warning "Nenhum volume configurado ainda"
    else
        cat "$HOME/.icloudpd_volume_config"
    fi
    
    read -p "Pressione Enter..." 
    show_main_menu
}

# MODO CLI
handle_cli_mode() {
    case "${1:-}" in
        --list)
            list_volumes
            ;;
        --select)
            select_volume_interactive
            ;;
        --mount)
            mount_external_volume
            ;;
        --validate)
            if [ -f "$HOME/.icloudpd_volume_config" ]; then
                source "$HOME/.icloudpd_volume_config"
                validate_volume_access "$BACKUP_VOLUME"
            fi
            ;;
        --setup)
            if [ -f "$HOME/.icloudpd_volume_config" ]; then
                source "$HOME/.icloudpd_volume_config"
                setup_volume_structure "$BACKUP_VOLUME"
            fi
            ;;
        --config)
            if [ -f "$HOME/.icloudpd_volume_config" ]; then
                cat "$HOME/.icloudpd_volume_config"
            else
                warning "Nenhum volume configurado"
            fi
            ;;
        --help)
            cat << 'EOF'
Uso: volume_manager.sh [OPÇÃO]

Opções:
  --list              Listar volumes disponíveis
  --select            Selecionar volume (interativo)
  --mount             Montar volume externo
  --validate          Validar volume configurado
  --setup             Criar estrutura no volume
  --config            Mostrar configuração atual
  --help              Mostrar esta ajuda

Exemplos:
  ./volume_manager.sh --list
  ./volume_manager.sh --select
  source $(./volume_manager.sh --config | grep BACKUP_VOLUME)
EOF
            ;;
        *)
            show_main_menu
            ;;
    esac
}

# MAIN
main() {
    if [ $# -gt 0 ]; then
        handle_cli_mode "$@"
    else
        show_main_menu
    fi
}

main "$@"
