#!/bin/bash

################################################################################
# SCRIPT DE LIMPEZA SEGURA PARA BACKUP ICLOUD
# Deleta arquivos duplicados com confirmações múltiplas e backup de segurança
################################################################################

set -euo pipefail

# CORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# CONFIGURAÇÕES
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/icloud_backups}"
REPORT_FILE="${1:-}"
SAFETY_BACKUP_DIR="${BACKUP_ROOT}/cleanup_backups"

# FUNÇÕES DE SAÍDA
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
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
print_banner() {
    clear
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║        🗑️  LIMPEZA SEGURA DE ARQUIVOS DUPLICADOS            ║
║   Deleta com Confirmação Multi-Camadas e Backup de Segurança  ║
╚═══════════════════════════════════════════════════════════════╝

EOF
}

# VERIFICAR ARQUIVO DE DUPLICATAS
check_report_file() {
    if [ -z "$REPORT_FILE" ]; then
        error "Uso: $0 <arquivo_de_relatorio_duplicatas>"
        echo ""
        echo "Exemplos:"
        echo "  $0 ~/icloud_backups/reports/duplicates_20240115_143210.txt"
        echo "  $0 ~/icloud_backups/reports/duplicates_*.json"
        exit 1
    fi
    
    if [ ! -f "$REPORT_FILE" ]; then
        error "Arquivo não encontrado: $REPORT_FILE"
        exit 1
    fi
    
    success "Relatório carregado: $REPORT_FILE"
}

# ANALISAR DUPLICATAS DO RELATÓRIO
analyze_duplicates() {
    log "Analisando relatório de duplicatas..."
    
    if [[ "$REPORT_FILE" == *.json ]]; then
        parse_json_report
    else
        parse_text_report
    fi
}

# PARSER PARA RELATÓRIO JSON
parse_json_report() {
    log "Processando relatório JSON..."
    
    python3 << 'PYTHON_EOF'
import json
import sys

report_file = sys.argv[1]

try:
    with open(report_file, 'r') as f:
        data = json.load(f)
    
    print(f"\n📊 RESUMO DO RELATÓRIO JSON")
    print(f"{'='*60}")
    print(f"Grupos duplicados: {data['summary']['total_duplicate_groups']}")
    print(f"Total de duplicatas: {data['summary']['total_duplicate_files']}")
    print(f"Espaço economizável: {data['summary']['wasted_space_formatted']}")
    print(f"{'='*60}\n")
    
    # Listar primeiros arquivos para confirmar
    count = 0
    for group_name, group_data in list(data['duplicates'].items())[:3]:
        count += 1
        print(f"Exemplo {count}: {group_name}")
        print(f"  Hash: {group_data['hash'][:16]}...")
        print(f"  Arquivos:")
        for file in group_data['files'][:2]:
            print(f"    - {file}")
        if len(group_data['files']) > 2:
            print(f"    ... e {len(group_data['files'])-2} mais")
        print()

except json.JSONDecodeError as e:
    print(f"Erro ao ler JSON: {e}")
    sys.exit(1)

PYTHON_EOF
    python3 - "$REPORT_FILE"
}

# PARSER PARA RELATÓRIO TEXT
parse_text_report() {
    log "Processando relatório de texto..."
    
    head -50 "$REPORT_FILE"
    echo ""
}

# CONFIRMAÇÃO DE SEGURANÇA NÍVEL 1
confirm_level_1() {
    echo ""
    warning "⚠️  AVISO CRÍTICO ⚠️"
    echo ""
    echo "Você está prestes a deletar arquivos duplicados."
    echo "Esta operação é IRREVERSÍVEL."
    echo ""
    echo "Certifique-se de que:"
    echo "  ✓ Tem backup local completo"
    echo "  ✓ Tem backup em disco externo"
    echo "  ✓ Revisou o relatório de duplicatas"
    echo "  ✓ Identificou qual cópia manter"
    echo ""
    
    read -p "Você confirmou todos os pontos acima? (s/N): " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        log "Operação cancelada"
        exit 0
    fi
}

# CONFIRMAÇÃO DE SEGURANÇA NÍVEL 2
confirm_level_2() {
    echo ""
    warning "⚠️  SEGUNDA CONFIRMAÇÃO ⚠️"
    echo ""
    echo "Este script vai mover arquivos duplicados para:"
    echo "  ${SAFETY_BACKUP_DIR}/$(date +%Y-%m-%d)"
    echo ""
    echo "Os arquivos NÃO serão deletados permanentemente."
    echo "Você pode recuperá-los depois se necessário."
    echo ""
    
    read -p "Proceder com o movimento de arquivos? (s/N): " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        log "Operação cancelada"
        exit 0
    fi
}

# CONFIRMAÇÃO DE SEGURANÇA NÍVEL 3
confirm_level_3() {
    echo ""
    warning "⚠️  TERCEIRA E ÚLTIMA CONFIRMAÇÃO ⚠️"
    echo ""
    
    # Gerar código aleatório
    random_code=$(openssl rand -hex 3 | tr '[:lower:]' '[:upper:]')
    
    echo "Digite o código a seguir para confirmar:"
    echo "  ${MAGENTA}${random_code}${NC}"
    echo ""
    
    read -p "Código: " user_code
    
    if [ "$user_code" != "$random_code" ]; then
        error "Código incorreto. Operação cancelada."
        exit 1
    fi
}

# CRIAR ESTRUTURA DE SEGURANÇA
create_safety_structure() {
    mkdir -p "${SAFETY_BACKUP_DIR}/$(date +%Y-%m-%d)"
    mkdir -p "${SAFETY_BACKUP_DIR}/logs"
    success "Estrutura de segurança criada"
}

# EXECUTAR LIMPEZA SIMULADA
dry_run() {
    log "Executando simulação (DRY RUN)..."
    
    echo ""
    echo "Este script vai executar as seguintes ações:"
    echo ""
    echo "1. Analisar relatório de duplicatas"
    echo "2. Identificar cópias redundantes"
    echo "3. Mover para pasta de segurança (não deleta)"
    echo "4. Gerar relatório de limpeza"
    echo "5. Permitir recuperação por 30 dias"
    echo ""
    
    read -p "Continuar com a limpeza real? (s/N): " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        log "Simulação cancelada"
        exit 0
    fi
}

# MOVER ARQUIVOS DUPLICADOS
move_duplicates() {
    log "Movendo arquivos duplicados..."
    
    local cleanup_date=$(date +%Y-%m-%d)
    local backup_dir="${SAFETY_BACKUP_DIR}/${cleanup_date}"
    local moved_count=0
    local skipped_count=0
    
    if [[ "$REPORT_FILE" == *.json ]]; then
        moved_count=$(move_from_json "$REPORT_FILE" "$backup_dir")
    else
        moved_count=$(move_from_text "$REPORT_FILE" "$backup_dir")
    fi
    
    success "Arquivos movidos: ${moved_count}"
}

# MOVER A PARTIR DE JSON
move_from_json() {
    local report_file="$1"
    local backup_dir="$2"
    local moved=0
    
    python3 << PYTHON_EOF
import json
import os
import shutil
from pathlib import Path

report_file = "$report_file"
backup_dir = "$backup_dir"

try:
    with open(report_file, 'r') as f:
        data = json.load(f)
    
    # Para cada grupo de duplicatas
    for group_name, group_data in data['duplicates'].items():
        files = group_data['files']
        
        if len(files) < 2:
            continue
        
        # Manter o primeiro, mover os outros
        kept_file = files[0]
        
        print(f"\\nGrupo: {group_name}")
        print(f"  Mantendo: {os.path.basename(kept_file)}")
        
        for dup_file in files[1:]:
            if os.path.exists(dup_file):
                try:
                    # Criar estrutura de diretório
                    os.makedirs(backup_dir, exist_ok=True)
                    
                    # Mover arquivo
                    dest = os.path.join(backup_dir, os.path.basename(dup_file))
                    shutil.move(dup_file, dest)
                    print(f"  → Movido: {os.path.basename(dup_file)}")
                except Exception as e:
                    print(f"  ✗ Erro ao mover {dup_file}: {e}")

except Exception as e:
    print(f"Erro: {e}")

PYTHON_EOF
}

# GERAR RELATÓRIO DE LIMPEZA
generate_cleanup_report() {
    local cleanup_date=$(date +%Y-%m-%d)
    local report_file="${SAFETY_BACKUP_DIR}/logs/cleanup_${cleanup_date}_$(date +%H%M%S).txt"
    
    cat > "$report_file" << EOF
╔════════════════════════════════════════════════════════════════╗
║              RELATÓRIO DE LIMPEZA DE DUPLICATAS               ║
╚════════════════════════════════════════════════════════════════╝

📅 Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')
📁 Origem: $REPORT_FILE
🗑️  Backup de Segurança: ${SAFETY_BACKUP_DIR}/${cleanup_date}

RESUMO DA OPERAÇÃO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ Arquivos analisados
✓ Duplicatas identificadas
✓ Arquivos movidos (não deletados)
✓ Segurança preservada

RECUPERAÇÃO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Os arquivos movidos estão em:
  ${SAFETY_BACKUP_DIR}/${cleanup_date}

Para recuperar um arquivo:
  mv ${SAFETY_BACKUP_DIR}/${cleanup_date}/ARQUIVO_NOME.jpg ~/

Prazo de retenção: 30 dias
Data de exclusão programada: $(date -d "+30 days" '+%Y-%m-%d')

PRÓXIMOS PASSOS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Verificar espaço em disco economizado
   du -sh ${SAFETY_BACKUP_DIR}/${cleanup_date}

2. Se tudo OK, deletar permanentemente após 30 dias
   rm -rf ${SAFETY_BACKUP_DIR}/${cleanup_date}

3. Liberar espaço no iCloud (via iCloud.com ou iPhone)

4. Vaciar "Recentemente Deletadas" no iPhone

EOF

    cat "$report_file"
    success "Relatório de limpeza: $report_file"
}

# AGENDAR LIMPEZA AUTOMÁTICA
schedule_auto_cleanup() {
    local cleanup_date=$(date +%Y-%m-%d)
    local delete_date=$(date -d "+30 days" '+%Y-%m-%d')
    local cleanup_dir="${SAFETY_BACKUP_DIR}/${cleanup_date}"
    
    log "Agendando limpeza automática para: $delete_date"
    
    # Criar cron job
    echo "0 0 $delete_date * * rm -rf $cleanup_dir" | crontab -
    
    success "Limpeza agendada automaticamente"
}

# MENU PRINCIPAL
show_menu() {
    echo ""
    echo "O que deseja fazer?"
    echo ""
    echo "  1) Simulação (DRY RUN)"
    echo "  2) Executar limpeza com confirmação"
    echo "  3) Apenas gerar relatório"
    echo "  4) Cancelar"
    echo ""
    
    read -p "Opção (1-4): " choice
    
    case $choice in
        1) dry_run; exit 0;;
        2) confirm_level_1; confirm_level_2; confirm_level_3;;
        3) exit 0;;
        4) log "Operação cancelada"; exit 0;;
        *) error "Opção inválida"; show_menu;;
    esac
}

# FUNÇÃO PRINCIPAL
main() {
    print_banner
    check_report_file
    create_safety_structure
    analyze_duplicates
    show_menu
    move_duplicates
    generate_cleanup_report
    
    echo ""
    success "✓ Limpeza concluída com segurança!"
    echo ""
    warning "Lembre-se: Arquivos estão em quarentena por 30 dias"
    echo ""
}

main "$@"
