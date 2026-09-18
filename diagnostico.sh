#!/bin/bash

################################################################################
# DIAGNÓSTICO DO SISTEMA DE BACKUP
# Identifica e corrige problemas comuns
################################################################################

set -euo pipefail

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
║  🔍 DIAGNÓSTICO - SISTEMA DE BACKUP ICLOUD                   ║
║  Identifica e corrige problemas                              ║
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

# TEST: SISTEMA
test_system() {
    echo ""
    echo -e "${CYAN}═══ TESTE 1: SISTEMA OPERACIONAL ═══${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local macos_version=$(sw_vers -productVersion)
        success "macOS $macos_version"
    else
        error "Não é macOS: $OSTYPE"
        return 1
    fi
}

# TEST: BREW
test_brew() {
    echo ""
    echo -e "${CYAN}═══ TESTE 2: HOMEBREW ═══${NC}"
    
    if command -v brew &> /dev/null; then
        local brew_version=$(brew --version | head -1)
        success "$brew_version"
    else
        error "Homebrew não encontrado"
        echo ""
        echo "Instalar:"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        return 1
    fi
}

# TEST: PYTHON
test_python() {
    echo ""
    echo -e "${CYAN}═══ TESTE 3: PYTHON ═══${NC}"
    
    if command -v python3 &> /dev/null; then
        local python_version=$(python3 --version 2>&1)
        success "$python_version"
    else
        error "Python 3 não encontrado"
        echo "Instalar: brew install python3"
        return 1
    fi
    
    # Testar Pillow
    echo ""
    echo "Testando Pillow..."
    if python3 -c "from PIL import Image; print('  ✓ Pillow importado com sucesso')" 2>&1; then
        success "Pillow funciona"
    else
        error "Pillow com problema"
        echo "Corrigir:"
        echo "  pip3 install --upgrade Pillow"
        return 1
    fi
}

# TEST: ICLOUDPD
test_icloudpd() {
    echo ""
    echo -e "${CYAN}═══ TESTE 4: ICLOUDPD ═══${NC}"
    
    if command -v icloudpd &> /dev/null; then
        success "icloudpd encontrado"
        icloudpd --version 2>&1 || warning "Versão não conseguida"
    else
        error "icloudpd não encontrado"
        echo "Instalar:"
        echo "  pip3 install icloudpd"
        return 1
    fi
}

# TEST: VOLUMES
test_volumes() {
    echo ""
    echo -e "${CYAN}═══ TESTE 5: VOLUMES DISPONÍVEIS ═══${NC}"
    
    echo ""
    echo "Volume principal (Macintosh HD):"
    df -h "$HOME" | tail -1 | awk '{printf "  Espaço: %s/%s (Disponível: %s)\n", $3, $2, $4}'
    
    echo ""
    echo "Volumes externos:"
    
    local found_external=0
    for volume in /Volumes/*; do
        if [ ! -L "$volume" ] && [ "$volume" != "/Volumes/Macintosh HD" ] && [ "$volume" != "/Volumes/Recovery" ]; then
            local name=$(basename "$volume")
            local space=$(df -h "$volume" 2>/dev/null | tail -1 | awk '{printf "Disponível: %s/%s", $4, $2}')
            echo "  ${GREEN}✓${NC} $name ($space)"
            found_external=$((found_external + 1))
        fi
    done
    
    if [ $found_external -eq 0 ]; then
        warning "Nenhum volume externo encontrado"
        echo "  Conectar um disco via Thunderbolt ou USB"
    fi
}

# TEST: PERMISSÕES
test_permissions() {
    echo ""
    echo -e "${CYAN}═══ TESTE 6: PERMISSÕES ═══${NC}"
    
    # Verificar ~/.local/bin
    if [ -d "$HOME/.local/bin" ]; then
        if [ -w "$HOME/.local/bin" ]; then
            success "$HOME/.local/bin tem permissões de escrita"
        else
            warning "$HOME/.local/bin sem permissão de escrita"
            echo "Corrigir: chmod 755 $HOME/.local/bin"
        fi
    else
        warning "$HOME/.local/bin não existe"
        echo "Criar: mkdir -p $HOME/.local/bin"
    fi
    
    # Verificar volumes externos
    for volume in /Volumes/*; do
        if [ ! -L "$volume" ] && [ "$volume" != "/Volumes/Macintosh HD" ] && [ "$volume" != "/Volumes/Recovery" ]; then
            if [ -w "$volume" ]; then
                success "$(basename "$volume") tem permissões de escrita"
            else
                error "$(basename "$volume") SEM permissão de escrita"
                echo "Corrigir: sudo chmod 755 '$volume'"
            fi
        fi
    done
}

# TEST: PATH
test_path() {
    echo ""
    echo -e "${CYAN}═══ TESTE 7: PATH E ATALHOS ═══${NC}"
    
    # Verificar se ~/.local/bin está no PATH
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        success "$HOME/.local/bin está no PATH"
    else
        warning "$HOME/.local/bin NÃO está no PATH"
        echo "Adicionar a ~/.zshrc ou ~/.bash_profile:"
        echo "  export PATH=\"\$PATH:\$HOME/.local/bin\""
        echo ""
        echo "Depois recarregar:"
        echo "  source ~/.zshrc"
    fi
}

# TEST: CONFIG FILE
test_config() {
    echo ""
    echo -e "${CYAN}═══ TESTE 8: ARQUIVO DE CONFIGURAÇÃO ═══${NC}"
    
    if [ -f "$HOME/.icloudpd_volume_config" ]; then
        success "Arquivo de configuração encontrado"
        echo ""
        echo "Conteúdo:"
        cat "$HOME/.icloudpd_volume_config" | grep "export" | sed 's/^/  /'
    else
        warning "Arquivo de configuração não encontrado"
        echo "Será criado ao rodar setup_macos_v2.sh"
    fi
}

# RESUMO
show_summary() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}PROBLEMAS ENCONTRADOS E SOLUÇÕES${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

# RECOMENDAÇÕES
show_recommendations() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}PRÓXIMOS PASSOS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo "1. Se houver erros acima, execute as correções recomendadas"
    echo ""
    echo "2. Recarregue o Terminal:"
    echo "   ${CYAN}source ~/.zshrc${NC}"
    echo ""
    echo "3. Execute o setup (versão 2, corrigida):"
    echo "   ${CYAN}chmod +x setup_macos_v2.sh${NC}"
    echo "   ${CYAN}./setup_macos_v2.sh${NC}"
    echo ""
    echo "4. Após setup, faça o backup:"
    echo "   ${CYAN}icloud-backup${NC}"
    echo ""
}

# MAIN
main() {
    test_system || true
    test_brew || true
    test_python || true
    test_icloudpd || true
    test_volumes || true
    test_permissions || true
    test_path || true
    test_config || true
    
    show_summary
    show_recommendations
    
    echo ""
    success "Diagnóstico concluído"
    echo ""
}

main "$@"
