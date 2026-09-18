#!/usr/bin/env python3

################################################################################
# DETECTOR DE DUPLICATAS - VERSÃO CORRIGIDA
# Trata lista vazia de arquivos sem crashar
################################################################################

import os
import sys
import json
import hashlib
from pathlib import Path
from collections import defaultdict

# CORES
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
NC = '\033[0m'

def log(msg):
    print(f"{BLUE}[*]{NC} {msg}")

def success(msg):
    print(f"{GREEN}[✓]{NC} {msg}")

def error(msg):
    print(f"{RED}[✗]{NC} {msg}")

def warning(msg):
    print(f"{YELLOW}[⚠]{NC} {msg}")

def get_file_hash(filepath, algorithm='sha256'):
    """Calcular hash de um arquivo"""
    hash_func = hashlib.new(algorithm)
    
    try:
        with open(filepath, 'rb') as f:
            while chunk := f.read(8192):
                hash_func.update(chunk)
        return hash_func.hexdigest()
    except Exception as e:
        error(f"Erro ao processar {filepath}: {e}")
        return None

def get_file_size(filepath):
    """Obter tamanho do arquivo em bytes"""
    try:
        return os.path.getsize(filepath)
    except:
        return 0

def scan_directory(directory):
    """Escanear diretório e retornar lista de arquivos"""
    files = []
    
    try:
        for root, dirs, filenames in os.walk(directory):
            for filename in filenames:
                filepath = os.path.join(root, filename)
                files.append(filepath)
        return files
    except Exception as e:
        error(f"Erro ao escanear diretório: {e}")
        return []

def find_duplicates(files):
    """Encontrar duplicatas por hash"""
    
    if not files:
        warning("Nenhum arquivo para analisar")
        return {}, {}
    
    hashes = defaultdict(list)
    file_sizes = {}
    
    print(f"\nProcessando {len(files)} arquivos...")
    
    for i, filepath in enumerate(files, 1):
        print(f"  [{i}/{len(files)}] {os.path.basename(filepath)}", end='\r')
        
        file_hash = get_file_hash(filepath)
        if file_hash:
            hashes[file_hash].append(filepath)
            file_sizes[filepath] = get_file_size(filepath)
    
    print(" " * 80, end='\r')
    
    # Filtrar apenas hashes com múltiplos arquivos
    duplicates = {h: files for h, files in hashes.items() if len(files) > 1}
    
    return duplicates, file_sizes

def main():
    if len(sys.argv) < 2:
        print(f"Uso: {sys.argv[0]} <diretório>")
        sys.exit(1)
    
    directory = sys.argv[1]
    
    if not os.path.isdir(directory):
        error(f"Diretório não encontrado: {directory}")
        sys.exit(1)
    
    print("")
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║  🔍 DETECTOR DE DUPLICATAS                                    ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print("")
    
    log(f"Escaneando: {directory}")
    
    # Escanear arquivos
    files = scan_directory(directory)
    
    if not files:
        warning("Nenhum arquivo encontrado no diretório")
        print("")
        sys.exit(0)
    
    log(f"Total de arquivos encontrados: {len(files)}")
    
    # Procurar duplicatas
    print("")
    log("Procurando duplicatas...")
    duplicates, file_sizes = find_duplicates(files)
    
    # Gerar relatório
    print("")
    if not duplicates:
        success("Nenhuma duplicata encontrada! ✓")
        print("")
        sys.exit(0)
    
    # Mostrar duplicatas encontradas
    print("")
    print(f"{CYAN}📊 DUPLICATAS ENCONTRADAS: {len(duplicates)}{NC}")
    print("─" * 64)
    print("")
    
    total_wasted = 0
    duplicate_count = 0
    
    for file_hash, file_list in sorted(duplicates.items()):
        duplicate_count += len(file_list) - 1
        
        if len(file_list) > 1:
            size = file_sizes.get(file_list[0], 0)
            wasted = size * (len(file_list) - 1)
            total_wasted += wasted
            
            print(f"{YELLOW}Hash: {file_hash[:16]}...{NC}")
            print(f"  Quantidade: {len(file_list)} cópias")
            print(f"  Tamanho de cada: {size / (1024*1024):.2f} MB")
            print(f"  Espaço desperdiçado: {wasted / (1024*1024):.2f} MB")
            print("")
            
            for i, filepath in enumerate(file_list, 1):
                print(f"    {i}. {filepath}")
            print("")
    
    # Resumo
    print("─" * 64)
    print(f"{GREEN}✓ RESUMO{NC}")
    print(f"  Duplicatas encontradas: {len(duplicates)}")
    print(f"  Arquivos duplicados: {duplicate_count}")
    print(f"  Espaço desperdiçado: {total_wasted / (1024*1024*1024):.2f} GB")
    print("")
    
    success("Análise concluída!")
    print("")

if __name__ == "__main__":
    main()
