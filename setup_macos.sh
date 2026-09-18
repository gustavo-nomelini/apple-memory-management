#!/bin/bash

################################################################################
# SETUP RÁPIDO MACOS - BACKUP ICLOUD COM VOLUMES (FIXED)
# Corrigido: Detecção de volumes, validação, loops infinitos
################################################################################

set -uo pipefail  # Sem -e para não parar em erros de teste

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
║  🍎 SETUP MACOS FIXED - BACKUP ICLOUD COM VOLUMES            ║
║  Versão Corrigida - Sem loops, testes reais                  ║
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

# CHECK MACOS
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        error "Este script é específico para macOS"
        exit 1
    fi
    success "Sistema operacional: macOS"
}

# INSTALAR BREW
install_brew() {
    if command -v brew &> /dev/null; then
        success "Homebrew já instalado"
        return 0
    fi
    
    warning "Homebrew não encontrado. Instalando..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error "Falha ao instalar Homebrew"
        return 1
    }
    success "Homebrew instalado"
}

# INSTALAR DEPENDÊNCIAS
install_dependencies() {
    log "Instalando dependências..."
    
    # Python 3
    if ! command -v python3 &> /dev/null; then
        log "Instalando Python 3..."
        brew install python3
    else
        success "Python 3 já instalado"
    fi
    
    # icloudpd
    if ! pip3 show icloudpd &> /dev/null 2>&1; then
        log "Instalando icloudpd..."
        pip3 install icloudpd
    else
        success "icloudpd já instalado"
    fi
    
    # Pillow
    if ! python3 -c "from PIL import Image" 2>/dev/null; then
        log "Instalando Pillow..."
        pip3 install Pillow
    else
        success "Pillow já instalado"
    fi
    
    # Coreutils
    if ! command -v gsha256sum &> /dev/null; then
        log "Instalando coreutils..."
        brew install coreutils
    else
        success "coreutils já instalado"
    fi
}

# TESTAR INSTALAÇÃO
test_installation() {
    log "Testando instalação..."
    echo ""
    
    # Python
    if python3 -c "import sys; print(f'Python {sys.version.split()[0]}')" 2>&1; then
        success "Python OK"
    else
        error "Python teste falhou"
    fi
    
    # Pillow
    if python3 -c "from PIL import Image; print('Pillow OK')" 2>&1 | grep -q "Pillow"; then
        success "Pillow OK"
    else
        error "Pillow teste falhou"
    fi
    
    # icloudpd
    if icloudpd --version 2>&1 | head -1; then
        success "icloudpd OK"
    else
        error "icloudpd teste falhou"
    fi
    
    echo ""
}

# LISTAR VOLUMES (SIMPLES E DIRETO)
list_volumes() {
    echo ""
    echo -e "${CYAN}📱 VOLUMES DISPONÍVEIS:${NC}"
    echo ""
    
    local idx=1
    
    # Volume principal
    echo -e "${GREEN}${idx}${NC}) Macintosh HD (Disco Principal)"
    local size=$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $2}')
    local avail=$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    echo "   Total: $size | Disponível: $avail"
    echo ""
    idx=$((idx + 1))
    
    # Volumes externos - LISTA SIMPLES
    for volume in /Volumes/*; do
        # Pular links simbólicos e volumes do sistema
        if [ ! -L "$volume" ] 2>/dev/null; then
            if [ "$volume" != "/Volumes/Macintosh HD" ] && [ "$volume" != "/Volumes/Recovery" ]; then
                local name=$(basename "$volume")
                local size=$(df -h "$volume" 2>/dev/null | awk 'NR==2 {print $2}')
                local avail=$(df -h "$volume" 2>/dev/null | awk 'NR==2 {print $4}')
                
                echo -e "${GREEN}${idx}${NC}) $name"
                echo "   Total: $size | Disponível: $avail"
                echo ""
                idx=$((idx + 1))
            fi
        fi
    done
}

# SELECIONAR VOLUME (SEM LOOPS)
select_volume() {
    list_volumes
    
    local max_volumes=$idx
    
    read -p "Qual volume deseja usar? (1-$((max_volumes - 1))): " choice
    
    # VALIDAÇÃO INPUT
    if [ -z "$choice" ] || ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        error "Opção inválida: $choice"
        exit 1
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -ge "$max_volumes" ]; then
        error "Número fora do range: 1-$((max_volumes - 1))"
        exit 1
    fi
    
    # MAPEAR SELEÇÃO PARA VOLUME
    if [ "$choice" = "1" ]; then
        echo "$HOME"
        return 0
    fi
    
    # Contar até a opção selecionada
    local current_idx=1
    current_idx=$((current_idx + 1))  # Skip volume principal
    
    for volume in /Volumes/*; do
        if [ ! -L "$volume" ] 2>/dev/null; then
            if [ "$volume" != "/Volumes/Macintosh HD" ] && [ "$volume" != "/Volumes/Recovery" ]; then
                if [ "$current_idx" = "$choice" ]; then
                    echo "$volume"
                    return 0
                fi
                current_idx=$((current_idx + 1))
            fi
        fi
    done
    
    error "Volume não encontrado"
    exit 1
}

# VALIDAR DISCO
validate_disk() {
    local disk_path="$1"
    
    log "Validando disco: $disk_path"
    
    # 1. Verificar se existe
    if [ ! -d "$disk_path" ]; then
        error "Diretório não encontrado: $disk_path"
        return 1
    fi
    
    success "Diretório existe"
    
    # 2. Verificar permissões de escrita
    if [ ! -w "$disk_path" ]; then
        warning "Sem permissão de escrita em: $disk_path"
        return 1
    fi
    
    success "Tem permissão de escrita"
    
    # 3. Verificar espaço
    local available=$(df "$disk_path" 2>/dev/null | awk 'NR==2 {print $4}')
    local available_gb=$((available / 1024 / 1024))
    
    if [ "$available_gb" -lt 50 ]; then
        warning "Espaço baixo! Disponível: ${available_gb}GB (Recomendado: 100GB+)"
        read -p "Continuar mesmo assim? (s/N): " cont
        if [[ "$cont" != "s" ]]; then
            return 1
        fi
    else
        success "Espaço suficiente: ${available_gb}GB disponível"
    fi
    
    return 0
}

# CRIAR ESTRUTURA
create_structure() {
    local disk_path="$1"
    
    log "Criando estrutura de diretórios..."
    
    mkdir -p "$disk_path/icloud_backups"/{downloads,archive,duplicates,logs,reports,temp,cleanup_backups}
    chmod 750 "$disk_path/icloud_backups" 2>/dev/null || true
    chmod 755 "$disk_path/icloud_backups"/{downloads,archive,logs,reports} 2>/dev/null || true
    chmod 700 "$disk_path/icloud_backups"/{duplicates,temp,cleanup_backups} 2>/dev/null || true
    
    success "Estrutura criada em: $disk_path/icloud_backups"
}

# CRIAR CONFIG
create_config() {
    local disk_path="$1"
    local config_file="$HOME/.icloudpd_volume_config"
    
    cat > "$config_file" << EOF
#!/bin/bash
# Configuração de Volume para Backup iCloud
# Gerado: $(date)

export BACKUP_VOLUME="$disk_path"
export BACKUP_ROOT="\$BACKUP_VOLUME/icloud_backups"
export ICLOUD_USERNAME=""

EOF

    success "Configuração salva: $config_file"
}

# CRIAR ATALHOS
create_aliases() {
    log "Criando atalhos..."
    
    local shell_rc=""
    
    # Detectar shell
    if [ -f "$HOME/.zshrc" ]; then
        shell_rc="$HOME/.zshrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        shell_rc="$HOME/.bash_profile"
    else
        shell_rc="$HOME/.bashrc"
    fi
    
    # Verificar se já existem
    if ! grep -q "alias icloud-backup" "$shell_rc" 2>/dev/null; then
        cat >> "$shell_rc" << 'EOF'

# Atalhos do Sistema de Backup iCloud
alias icloud-backup='backup_icloud_macos.sh'
alias icloud-analyze='python3 duplicate_detector.py'
alias icloud-cleanup='safe_cleanup.sh'
alias icloud-volumes='volume_manager.sh'

EOF
    fi
    
    success "Atalhos criados em: $shell_rc"
}

# RESUMO
show_summary() {
    local disk_path="$1"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ SETUP COMPLETADO COM SUCESSO!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo "📁 Configuração:"
    echo "   Volume: $disk_path"
    echo "   Backup em: $disk_path/icloud_backups"
    echo ""
    
    echo "🚀 Próximos Passos:"
    echo ""
    echo "1. Recarregar Terminal:"
    echo "   ${CYAN}source ~/.zshrc${NC}"
    echo ""
    echo "2. Fazer backup:"
    echo "   ${CYAN}./backup_icloud_macos.sh${NC}"
    echo "   ou"
    echo "   ${CYAN}icloud-backup${NC}"
    echo ""
    echo "3. Monitorar progresso (em outro terminal):"
    echo "   ${CYAN}./backup_monitor.sh --summary${NC}"
    echo ""
    
    echo "📖 Documentação:"
    echo "   GUIA_MACOS_VOLUMES.md"
    echo "   README.md"
    echo ""
}

# MAIN
main() {
    check_macos
    echo ""
    
    install_brew
    echo ""
    
    install_dependencies
    echo ""
    
    test_installation
    
    # SELECIONAR VOLUME (SEM LOOP)
    local selected_volume=$(select_volume)
    
    echo ""
    success "Volume selecionado: $selected_volume"
    echo ""
    
    # VALIDAR (SEM LOOP)
    if ! validate_disk "$selected_volume"; then
        error "Validação do disco falhou"
        echo ""
        echo "Soluções possíveis:"
        echo "  1. Verificar se o disco está conectado"
        echo "  2. Verificar permissões: sudo chmod 755 '$selected_volume'"
        echo "  3. Tentar novamente"
        exit 1
    fi
    echo ""
    
    # CRIAR ESTRUTURA
    create_structure "$selected_volume"
    echo ""
    
    # CRIAR CONFIG
    create_config "$selected_volume"
    echo ""
    
    # CRIAR ATALHOS
    create_aliases
    echo ""
    
    # RESUMO
    show_summary "$selected_volume"
    
    echo -e "${GREEN}✓ Pronto para começar!${NC}"
}

# Executar
main "$@"
