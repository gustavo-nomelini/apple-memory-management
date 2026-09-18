#!/bin/bash

################################################################################
# SETUP MACOS ULTRA-SIMPLES - SEM BUGS
# Código minimalista, direto, sem funções complexas
################################################################################

set -u  # Erro se variável indefinida
# Remover -e para não parar em testes

clear
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  🍎 SETUP MACOS - ULTRA SIMPLES (SEM BUGS)                   ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════════
# PASSO 1: Testar sistema
# ═══════════════════════════════════════════════════════════════════

echo -e "${BLUE}[*]${NC} Verificando sistema..."

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}[✗]${NC} Não é macOS"
    exit 1
fi
echo -e "${GREEN}[✓]${NC} macOS detectado"
echo ""

# ═══════════════════════════════════════════════════════════════════
# PASSO 2: Instalar brew se necessário
# ═══════════════════════════════════════════════════════════════════

if ! command -v brew &> /dev/null; then
    echo -e "${BLUE}[*]${NC} Instalando Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo -e "${GREEN}[✓]${NC} Homebrew já instalado"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# PASSO 3: Instalar dependências
# ═══════════════════════════════════════════════════════════════════

echo -e "${BLUE}[*]${NC} Verificando/instalando dependências..."

if ! command -v python3 &> /dev/null; then
    echo -e "${BLUE}  → Instalando Python 3...${NC}"
    brew install python3
else
    echo -e "${GREEN}  ✓ Python 3${NC}"
fi

if ! pip3 show icloudpd &> /dev/null 2>&1; then
    echo -e "${BLUE}  → Instalando icloudpd...${NC}"
    pip3 install icloudpd
else
    echo -e "${GREEN}  ✓ icloudpd${NC}"
fi

if ! python3 -c "from PIL import Image" 2>/dev/null; then
    echo -e "${BLUE}  → Instalando Pillow...${NC}"
    pip3 install Pillow
else
    echo -e "${GREEN}  ✓ Pillow${NC}"
fi

if ! command -v gsha256sum &> /dev/null; then
    echo -e "${BLUE}  → Instalando coreutils...${NC}"
    brew install coreutils
else
    echo -e "${GREEN}  ✓ coreutils${NC}"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# PASSO 4: Testar instalação
# ═══════════════════════════════════════════════════════════════════

echo -e "${BLUE}[*]${NC} Testando instalação..."

python3 --version 2>&1 | grep -q "Python" && echo -e "${GREEN}  ✓ Python${NC}" || echo -e "${YELLOW}  ⚠ Python${NC}"
python3 -c "from PIL import Image" 2>&1 | grep -q "Error" || echo -e "${GREEN}  ✓ Pillow${NC}"
icloudpd --version 2>&1 | head -1 | grep -q "version" && echo -e "${GREEN}  ✓ icloudpd${NC}" || echo -e "${YELLOW}  ⚠ icloudpd${NC}"

echo ""

# ═══════════════════════════════════════════════════════════════════
# PASSO 5: Listar volumes
# ═══════════════════════════════════════════════════════════════════

echo -e "${CYAN}📱 VOLUMES DISPONÍVEIS:${NC}"
echo ""

# Array para armazenar volumes
declare -a VOLUMES_ARRAY

# Volume 1: Principal
VOLUMES_ARRAY[1]="$HOME"
echo -e "${GREEN}1)${NC} Macintosh HD (Disco Principal)"
df -h "$HOME" 2>/dev/null | awk 'NR==2 {print "   Total: " $2 " | Disponível: " $4}' || echo "   Total: ? | Disponível: ?"
echo ""

# Volumes 2+: Externos
VOLUME_INDEX=2
for vol in /Volumes/*; do
    # Pular links simbólicos
    if [ ! -L "$vol" ] 2>/dev/null; then
        # Pular volumes do sistema
        if [ "$vol" != "/Volumes/Macintosh HD" ] && [ "$vol" != "/Volumes/Recovery" ]; then
            VOLUMES_ARRAY[$VOLUME_INDEX]="$vol"
            NOME=$(basename "$vol")
            echo -e "${GREEN}${VOLUME_INDEX})${NC} $NOME"
            df -h "$vol" 2>/dev/null | awk 'NR==2 {print "   Total: " $2 " | Disponível: " $4}' || echo "   Total: ? | Disponível: ?"
            echo ""
            VOLUME_INDEX=$((VOLUME_INDEX + 1))
        fi
    fi
done

# ═══════════════════════════════════════════════════════════════════
# PASSO 6: Selecionar volume (SEM LOOPS)
# ═══════════════════════════════════════════════════════════════════

echo ""
MAX_VOLUMES=$((VOLUME_INDEX - 1))
read -p "Qual volume deseja usar? (1-$MAX_VOLUMES): " CHOICE

# Validar entrada
if [ -z "$CHOICE" ] || ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}[✗]${NC} Opção inválida: $CHOICE"
    exit 1
fi

if [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$MAX_VOLUMES" ]; then
    echo -e "${RED}[✗]${NC} Número fora do range: 1-$MAX_VOLUMES"
    exit 1
fi

# Pegar volume selecionado
SELECTED_VOLUME="${VOLUMES_ARRAY[$CHOICE]}"

if [ -z "$SELECTED_VOLUME" ]; then
    echo -e "${RED}[✗]${NC} Volume não encontrado"
    exit 1
fi

echo ""
echo -e "${GREEN}[✓]${NC} Volume selecionado: $SELECTED_VOLUME"
echo ""

# ═══════════════════════════════════════════════════════════════════
# PASSO 7: Validar disco
# ═══════════════════════════════════════════════════════════════════

echo -e "${BLUE}[*]${NC} Validando disco..."

# Teste 1: Existe?
if [ ! -d "$SELECTED_VOLUME" ]; then
    echo -e "${RED}[✗]${NC} Diretório não existe: $SELECTED_VOLUME"
    exit 1
fi
echo -e "${GREEN}  ✓ Diretório existe${NC}"

# Teste 2: Tem permissão?
if [ ! -w "$SELECTED_VOLUME" ]; then
    echo -e "${RED}[✗]${NC} Sem permissão de escrita"
    echo "Tente: sudo chmod 755 '$SELECTED_VOLUME'"
    exit 1
fi
echo -e "${GREEN}  ✓ Tem permissão de escrita${NC}"

# Teste 3: Tem espaço?
AVAILABLE=$(df "$SELECTED_VOLUME" 2>/dev/null | awk 'NR==2 {print $4}')
AVAILABLE_GB=$((AVAILABLE / 1024 / 1024))

if [ "$AVAILABLE_GB" -lt 50 ]; then
    echo -e "${YELLOW}  ⚠ Espaço baixo: ${AVAILABLE_GB}GB${NC}"
    read -p "Continuar mesmo assim? (s/N): " CONT
    if [[ "$CONT" != "s" ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}  ✓ Espaço suficiente: ${AVAILABLE_GB}GB${NC}"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# PASSO 8: Criar estrutura
# ═══════════════════════════════════════════════════════════════════

echo -e "${BLUE}[*]${NC} Criando estrutura de diretórios..."

mkdir -p "$SELECTED_VOLUME/icloud_backups"/{downloads,archive,duplicates,logs,reports,temp,cleanup_backups} 2>/dev/null || true
chmod 755 "$SELECTED_VOLUME/icloud_backups" 2>/dev/null || true

echo -e "${GREEN}[✓]${NC} Estrutura criada: $SELECTED_VOLUME/icloud_backups"
echo ""

# ═══════════════════════════════════════════════════════════════════
# PASSO 9: Criar arquivo de configuração
# ═══════════════════════════════════════════════════════════════════

echo -e "${BLUE}[*]${NC} Criando configuração..."

CONFIG_FILE="$HOME/.icloudpd_volume_config"

cat > "$CONFIG_FILE" << EOF
#!/bin/bash
# Configuração de Volume para Backup iCloud
# Gerado: $(date)

export BACKUP_VOLUME="$SELECTED_VOLUME"
export BACKUP_ROOT="\$BACKUP_VOLUME/icloud_backups"
export ICLOUD_USERNAME=""

EOF

echo -e "${GREEN}[✓]${NC} Configuração salva: $CONFIG_FILE"
echo ""

# ═══════════════════════════════════════════════════════════════════
# PASSO 10: Criar atalhos
# ═══════════════════════════════════════════════════════════════════

echo -e "${BLUE}[*]${NC} Criando atalhos..."

SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bash_profile" ]; then
    SHELL_RC="$HOME/.bash_profile"
else
    SHELL_RC="$HOME/.bashrc"
fi

if [ ! -z "$SHELL_RC" ] && ! grep -q "alias icloud-backup" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'EOF'

# Atalhos do Sistema de Backup iCloud
alias icloud-backup='backup_icloud_macos.sh'
alias icloud-analyze='python3 duplicate_detector.py'
alias icloud-cleanup='safe_cleanup.sh'
alias icloud-volumes='volume_manager.sh'

EOF
fi

echo -e "${GREEN}[✓]${NC} Atalhos criados em: $SHELL_RC"
echo ""

# ═══════════════════════════════════════════════════════════════════
# RESUMO
# ═══════════════════════════════════════════════════════════════════

echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ SETUP COMPLETADO COM SUCESSO!${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📁 Configuração:"
echo "   Volume: $SELECTED_VOLUME"
echo "   Backup em: $SELECTED_VOLUME/icloud_backups"
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
echo "════════════════════════════════════════════════════════════"
echo ""
