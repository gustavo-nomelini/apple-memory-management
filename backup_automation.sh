#!/bin/bash

################################################################################
# AUTOMAÇÃO DE BACKUP - CONFIGURAR CRON JOBS
# Backup automático em horários específicos com notificações
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
BACKUP_SCRIPT_PATH="${BACKUP_SCRIPT_PATH:-$HOME/.local/bin/backup_icloud_macos.sh}"
BACKUP_VOLUME="${BACKUP_VOLUME:-$HOME}"
BACKUP_ROOT="${BACKUP_ROOT:-$BACKUP_VOLUME/icloud_backups}"
LOG_DIR="${BACKUP_ROOT}/logs"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}"

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

# BANNER
show_banner() {
    clear
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║  🤖 AUTOMAÇÃO DE BACKUP - CRON JOBS                          ║
║  Agendar backups automáticos em horários específicos          ║
╚═══════════════════════════════════════════════════════════════╝

EOF
}

# CRIAR SCRIPT WRAPPER
create_cron_wrapper() {
    local wrapper_path="$HOME/.local/bin/backup_icloud_cron.sh"
    
    log "Criando script wrapper para cron..."
    
    cat > "$wrapper_path" << 'EOF'
#!/bin/bash

# Script de backup para cron job
# Inclui logging, notificações e tratamento de erros

set -euo pipefail

# Carregar configuração
if [ -f "$HOME/.icloudpd_volume_config" ]; then
    source "$HOME/.icloudpd_volume_config"
fi

BACKUP_SCRIPT="${BACKUP_SCRIPT:-$HOME/.local/bin/backup_icloud_macos.sh}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/icloud_backups}"
LOG_FILE="${BACKUP_ROOT}/logs/cron_backup_$(date +%Y-%m-%d_%H-%M-%S).log"
BACKUP_START=$(date +%s)

# Criar log
mkdir -p "$(dirname "$LOG_FILE")"

echo "════════════════════════════════════════════" >> "$LOG_FILE"
echo "Backup automático iniciado: $(date)" >> "$LOG_FILE"
echo "════════════════════════════════════════════" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Executar backup
if "$BACKUP_SCRIPT" >> "$LOG_FILE" 2>&1; then
    BACKUP_END=$(date +%s)
    BACKUP_DURATION=$((BACKUP_END - BACKUP_START))
    
    # Extrair tamanho
    local backup_size=$(du -sh "$BACKUP_ROOT/downloads/$(date +%Y-%m-%d)" 2>/dev/null | cut -f1 || echo "N/A")
    local file_count=$(find "$BACKUP_ROOT/downloads/$(date +%Y-%m-%d)" -type f 2>/dev/null | wc -l || echo "0")
    
    # Log de sucesso
    echo "" >> "$LOG_FILE"
    echo "✓ BACKUP COMPLETADO COM SUCESSO" >> "$LOG_FILE"
    echo "Duração: $((BACKUP_DURATION / 60)) minutos" >> "$LOG_FILE"
    echo "Tamanho: $backup_size" >> "$LOG_FILE"
    echo "Arquivos: $file_count" >> "$LOG_FILE"
    echo "Log: $LOG_FILE" >> "$LOG_FILE"
    
    # Notificação (opcional)
    if [ ! -z "${NOTIFY_EMAIL:-}" ]; then
        echo "Backup do iCloud completado com sucesso" | \
        mail -s "✓ Backup iCloud - Sucesso" "$NOTIFY_EMAIL"
    fi
    
    # Notificação no macOS
    if command -v osascript &> /dev/null; then
        osascript << APPLESCRIPT
        display notification "Backup iCloud completado ($backup_size, $file_count arquivos)" \
          with title "Backup Automático" \
          subtitle "Sucesso"
APPLESCRIPT
    fi
    
    exit 0
else
    BACKUP_END=$(date +%s)
    BACKUP_DURATION=$((BACKUP_END - BACKUP_START))
    
    # Log de erro
    echo "" >> "$LOG_FILE"
    echo "✗ ERRO NO BACKUP" >> "$LOG_FILE"
    echo "Duração: $((BACKUP_DURATION / 60)) minutos" >> "$LOG_FILE"
    echo "Log: $LOG_FILE" >> "$LOG_FILE"
    
    # Notificação de erro
    if [ ! -z "${NOTIFY_EMAIL:-}" ]; then
        echo "Erro ao fazer backup do iCloud. Verifique: $LOG_FILE" | \
        mail -s "✗ Backup iCloud - ERRO" "$NOTIFY_EMAIL"
    fi
    
    # Notificação de erro no macOS
    if command -v osascript &> /dev/null; then
        osascript << APPLESCRIPT
        display notification "Erro ao executar backup iCloud" \
          with title "Backup Automático" \
          subtitle "Falha"
APPLESCRIPT
    fi
    
    exit 1
fi
EOF

    chmod +x "$wrapper_path"
    success "Script wrapper criado: $wrapper_path"
    return 0
}

# LISTAR CRON JOBS EXISTENTES
list_cron_jobs() {
    echo ""
    echo -e "${CYAN}Cron jobs existentes:${NC}"
    echo ""
    
    if crontab -l 2>/dev/null | grep -q "backup_icloud"; then
        crontab -l | grep "backup_icloud" | nl
    else
        echo "Nenhum backup iCloud agendado"
    fi
    
    echo ""
}

# PREDEFINIDAS
show_presets() {
    cat << 'EOF'

HORÁRIOS PRÉ-DEFINIDOS:

  1) Diariamente às 3:00 AM (Recomendado)
     0 3 * * * backup_icloud_cron.sh

  2) Toda segunda-feira às 2:00 AM
     0 2 * * 1 backup_icloud_cron.sh

  3) Toda sexta-feira às 11:00 PM
     0 23 * * 5 backup_icloud_cron.sh

  4) A cada 6 horas (24 horas de operação)
     0 */6 * * * backup_icloud_cron.sh

  5) A cada 12 horas
     0 */12 * * * backup_icloud_cron.sh

  6) Uma vez por dia à meia-noite
     0 0 * * * backup_icloud_cron.sh

  7) Customizado (você especifica)
     Digite o cronograma manualmente

═══════════════════════════════════════════════════════════════

FORMATO CRON: "minuto hora dia_mês mês dia_semana"

Exemplos:
  0 3 * * *    → 03:00 diariamente
  0 2 * * 1    → 02:00 segundas-feiras
  0 */6 * * *  → A cada 6 horas (00:00, 06:00, 12:00, 18:00)
  30 2 15 * *  → 02:30 no 15º dia de cada mês

EOF
}

# ADICIONAR CRON JOB
add_cron_job() {
    log "Adicionando novo cron job..."
    
    show_presets
    
    read -p "Qual opção? (1-7): " choice
    
    local cron_schedule=""
    
    case $choice in
        1) cron_schedule="0 3 * * *";;
        2) cron_schedule="0 2 * * 1";;
        3) cron_schedule="0 23 * * 5";;
        4) cron_schedule="0 */6 * * *";;
        5) cron_schedule="0 */12 * * *";;
        6) cron_schedule="0 0 * * *";;
        7) read -p "Digite o cronograma: " cron_schedule;;
        *) error "Opção inválida"; return 1;;
    esac
    
    # Verificar se já existe
    if crontab -l 2>/dev/null | grep -q "backup_icloud_cron"; then
        warning "Já existe um backup iCloud agendado"
        read -p "Deseja substituir? (s/N): " confirm
        if [[ "$confirm" != "s" ]]; then
            return 1
        fi
        # Remover anterior
        crontab -l | grep -v "backup_icloud_cron" | crontab -
    fi
    
    # Adicionar novo
    (crontab -l 2>/dev/null || echo ""; echo "$cron_schedule backup_icloud_cron.sh") | crontab -
    
    success "Cron job adicionado: $cron_schedule"
    list_cron_jobs
}

# REMOVER CRON JOB
remove_cron_job() {
    log "Removendo cron jobs do iCloud..."
    
    if ! crontab -l 2>/dev/null | grep -q "backup_icloud"; then
        warning "Nenhum backup iCloud agendado"
        return
    fi
    
    warning "Isso vai remover todos os backups automáticos!"
    read -p "Continuar? (s/N): " confirm
    
    if [[ "$confirm" != "s" ]]; then
        log "Operação cancelada"
        return
    fi
    
    crontab -l | grep -v "backup_icloud" | crontab -
    success "Cron jobs removidos"
}

# TESTAR CRON JOB
test_cron_job() {
    log "Executando teste de backup..."
    
    # Garantir que o wrapper existe
    if ! command -v backup_icloud_cron.sh &> /dev/null; then
        create_cron_wrapper
    fi
    
    log "Iniciando backup de teste..."
    
    if backup_icloud_cron.sh; then
        success "Teste completado com sucesso"
        
        # Mostrar último log
        local latest_log=$(ls -t "$LOG_DIR"/cron_backup_*.log 2>/dev/null | head -1)
        if [ ! -z "$latest_log" ]; then
            echo ""
            echo "Últimas linhas do log:"
            tail -20 "$latest_log"
        fi
    else
        error "Erro no teste"
    fi
}

# CONFIGURAR NOTIFICAÇÕES
configure_notifications() {
    echo ""
    echo -e "${CYAN}NOTIFICAÇÕES POR EMAIL${NC}"
    echo "─────────────────────────────────────────────────────"
    echo ""
    
    read -p "Email para notificações (ou deixar vazio): " email
    
    if [ ! -z "$email" ]; then
        # Adicionar à config
        echo "export NOTIFY_EMAIL='$email'" >> "$HOME/.icloudpd_volume_config"
        success "Email configurado: $email"
    else
        warning "Notificações por email desativadas"
    fi
    
    # Notificações macOS já funcionam automaticamente
    success "Notificações do macOS ativadas (automático)"
}

# VISUALIZAR LOGS RECENTES
show_recent_logs() {
    echo ""
    echo -e "${CYAN}ÚLTIMOS LOGS DE BACKUP${NC}"
    echo "─────────────────────────────────────────────────────"
    echo ""
    
    if [ ! -d "$LOG_DIR" ]; then
        warning "Nenhum log encontrado"
        return
    fi
    
    ls -lht "$LOG_DIR"/cron_backup_*.log 2>/dev/null | head -10 | \
    while read -r line; do
        echo "$line"
    done
    
    echo ""
    read -p "Ver conteúdo do último log? (s/N): " view_log
    
    if [[ "$view_log" == "s" ]]; then
        local latest=$(ls -t "$LOG_DIR"/cron_backup_*.log 2>/dev/null | head -1)
        if [ ! -z "$latest" ]; then
            less "$latest"
        fi
    fi
}

# MENU PRINCIPAL
show_main_menu() {
    clear
    show_banner
    
    cat << 'EOF'

1) Adicionar novo cron job (agendamento)
2) Listar cron jobs existentes
3) Remover cron jobs
4) Testar backup automático
5) Configurar notificações por email
6) Ver logs recentes
7) Ver formato cron
8) Sair

EOF
    
    read -p "Opção (1-8): " choice
    
    case $choice in
        1) create_cron_wrapper; add_cron_job; show_main_menu;;
        2) list_cron_jobs; read -p "Pressione Enter..."; show_main_menu;;
        3) remove_cron_job; show_main_menu;;
        4) test_cron_job; read -p "Pressione Enter..."; show_main_menu;;
        5) configure_notifications; show_main_menu;;
        6) show_recent_logs; show_main_menu;;
        7) show_presets; read -p "Pressione Enter..."; show_main_menu;;
        8) exit 0;;
        *) error "Opção inválida"; show_main_menu;;
    esac
}

# MAIN
main() {
    if [ $# -eq 0 ]; then
        show_main_menu
    else
        case "$1" in
            --add) create_cron_wrapper; add_cron_job;;
            --list) list_cron_jobs;;
            --remove) remove_cron_job;;
            --test) test_cron_job;;
            --help) cat << 'EOF'
Uso: backup_automation.sh [OPÇÃO]

Opções:
  (sem opção)  Menu interativo
  --add        Adicionar novo cron job
  --list       Listar agendamentos
  --remove     Remover agendamentos
  --test       Testar backup
  --help       Mostrar esta ajuda

Exemplos:
  ./backup_automation.sh         # Menu interativo
  ./backup_automation.sh --add   # Adicionar agendamento
  ./backup_automation.sh --list  # Ver agendamentos

Pré-requisitos:
  export BACKUP_SCRIPT_PATH="$HOME/.local/bin/backup_icloud_macos.sh"
  export BACKUP_VOLUME="/Volumes/seu_disco"
EOF
            ;;
            *)
                error "Opção desconhecida: $1"
                exit 1
                ;;
        esac
    fi
}

main "$@"
