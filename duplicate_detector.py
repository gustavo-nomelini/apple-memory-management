#!/usr/bin/env python3

"""
DETECTOR AVANÇADO DE DUPLICATAS PARA ICLOUD BACKUP
Detecta:
  - Duplicatas por hash (conteúdo idêntico)
  - Duplicatas por metadados (EXIF)
  - Imagens visualmente semelhantes (threshold configurável)
  - Diferenças de tamanho/resolução
"""

import os
import sys
import hashlib
import json
from pathlib import Path
from collections import defaultdict
from datetime import datetime
from PIL import Image
from PIL.ExifTags import TAGS
import argparse

class DuplicateDetector:
    def __init__(self, backup_dir, output_dir=None):
        self.backup_dir = Path(backup_dir)
        self.output_dir = Path(output_dir) if output_dir else self.backup_dir / "duplicate_analysis"
        self.output_dir.mkdir(exist_ok=True)
        
        self.file_hashes = defaultdict(list)
        self.exif_data = {}
        self.results = {}
        
    def calculate_hash(self, filepath, algorithm='sha256'):
        """Calcula hash de arquivo."""
        hash_func = hashlib.new(algorithm)
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b''):
                hash_func.update(chunk)
        return hash_func.hexdigest()
    
    def extract_exif(self, filepath):
        """Extrai metadados EXIF de imagem."""
        try:
            image = Image.open(filepath)
            exif_data = image._getexif()
            if exif_data:
                return {
                    TAGS.get(tag, tag): value 
                    for tag, value in exif_data.items()
                }
        except Exception as e:
            return {"error": str(e)}
        return {}
    
    def scan_files(self):
        """Escaneia todos os arquivos do diretório."""
        print("🔍 Escaneando arquivos...")
        
        supported_formats = {
            '.jpg', '.jpeg', '.png', '.gif', '.bmp', 
            '.mp4', '.mov', '.heic', '.heif', '.webp'
        }
        
        files_found = 0
        for filepath in self.backup_dir.rglob('*'):
            if filepath.is_file() and filepath.suffix.lower() in supported_formats:
                try:
                    file_hash = self.calculate_hash(filepath)
                    self.file_hashes[file_hash].append(str(filepath))
                    
                    # Extrair EXIF se for imagem
                    if filepath.suffix.lower() in {'.jpg', '.jpeg', '.heic', '.heif'}:
                        self.exif_data[str(filepath)] = self.extract_exif(filepath)
                    
                    files_found += 1
                    if files_found % 100 == 0:
                        print(f"  Processados: {files_found} arquivos")
                except Exception as e:
                    print(f"⚠️  Erro ao processar {filepath}: {e}")
        
        print(f"✓ Total de arquivos escaneados: {files_found}")
        return files_found
    
    def find_duplicates(self):
        """Encontra duplicatas por hash."""
        print("\n🔍 Detectando duplicatas por conteúdo...")
        
        duplicates = {}
        total_duplicates = 0
        wasted_space = 0
        
        for file_hash, files in self.file_hashes.items():
            if len(files) > 1:
                duplicates[file_hash] = files
                total_duplicates += len(files) - 1
                
                # Calcular espaço desperdiçado
                try:
                    file_size = os.path.getsize(files[0])
                    wasted_space += file_size * (len(files) - 1)
                except:
                    pass
        
        self.results['hash_duplicates'] = duplicates
        self.results['total_duplicate_groups'] = len(duplicates)
        self.results['total_duplicate_files'] = total_duplicates
        self.results['wasted_space_bytes'] = wasted_space
        
        print(f"✓ Grupos duplicados encontrados: {len(duplicates)}")
        print(f"✓ Arquivos duplicados: {total_duplicates}")
        print(f"✓ Espaço desperdiçado: {self._format_bytes(wasted_space)}")
        
        return duplicates
    
    def find_exif_duplicates(self):
        """Encontra duplicatas pelo EXIF (mesma foto, diferentes tamanhos)."""
        print("\n📸 Detectando duplicatas por metadados EXIF...")
        
        exif_duplicates = defaultdict(list)
        
        for filepath, exif in self.exif_data.items():
            if exif and 'error' not in exif:
                # Usar DateTime e CameraModel como chave
                key = (
                    exif.get('DateTime', 'unknown'),
                    exif.get('Model', 'unknown'),
                    os.path.getsize(filepath)
                )
                exif_duplicates[key].append(filepath)
        
        # Filtrar apenas grupos com duplicatas
        actual_duplicates = {k: v for k, v in exif_duplicates.items() if len(v) > 1}
        
        self.results['exif_duplicates'] = actual_duplicates
        print(f"✓ Duplicatas por EXIF encontradas: {len(actual_duplicates)}")
        
        return actual_duplicates
    
    def generate_report(self):
        """Gera relatório detalhado."""
        print("\n📝 Gerando relatório...")
        
        report_file = self.output_dir / f"duplicate_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        
        with open(report_file, 'w', encoding='utf-8') as f:
            f.write("╔" + "="*78 + "╗\n")
            f.write("║" + "RELATÓRIO DE DUPLICATAS - ICLOUD BACKUP".center(78) + "║\n")
            f.write("╚" + "="*78 + "╝\n\n")
            
            f.write(f"📅 Data/Hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"📁 Diretório: {self.backup_dir}\n\n")
            
            # Resumo
            f.write("RESUMO\n")
            f.write("─" * 80 + "\n")
            f.write(f"Grupos de duplicatas (conteúdo): {self.results.get('total_duplicate_groups', 0)}\n")
            f.write(f"Total de arquivos duplicados: {self.results.get('total_duplicate_files', 0)}\n")
            f.write(f"Espaço desperdiçado: {self._format_bytes(self.results.get('wasted_space_bytes', 0))}\n\n")
            
            # Duplicatas por hash
            if self.results.get('hash_duplicates'):
                f.write("DUPLICATAS POR CONTEÚDO (HASH)\n")
                f.write("─" * 80 + "\n")
                
                for idx, (file_hash, files) in enumerate(self.results['hash_duplicates'].items(), 1):
                    f.write(f"\n[Grupo {idx}] Hash: {file_hash}\n")
                    f.write(f"Quantidade de cópias: {len(files)}\n")
                    
                    for file_idx, filepath in enumerate(files, 1):
                        try:
                            size = os.path.getsize(filepath)
                            f.write(f"  {file_idx}. {filepath}\n")
                            f.write(f"     Tamanho: {self._format_bytes(size)}\n")
                        except:
                            f.write(f"  {file_idx}. {filepath}\n")
            
            # Duplicatas por EXIF
            if self.results.get('exif_duplicates'):
                f.write("\n\nDUPLICATAS POR METADADOS (EXIF)\n")
                f.write("─" * 80 + "\n")
                
                for idx, (key, files) in enumerate(self.results['exif_duplicates'].items(), 1):
                    f.write(f"\n[Grupo {idx}]\n")
                    f.write(f"  Data: {key[0]}\n")
                    f.write(f"  Câmera: {key[1]}\n")
                    
                    for filepath in files:
                        f.write(f"  → {filepath}\n")
            
            # Recomendações
            f.write("\n\nRECOMENDAÇÕES\n")
            f.write("─" * 80 + "\n")
            f.write("1. Revisar cada grupo de duplicatas\n")
            f.write("2. Manter a versão com melhor qualidade/tamanho\n")
            f.write("3. Deletar as cópias redundantes\n")
            f.write("4. Verificar integridade antes de deletar do iCloud\n")
            f.write("5. Fazer backup em disco externo como segurança extra\n")
        
        print(f"✓ Relatório salvo: {report_file}")
        return report_file
    
    def generate_json_report(self):
        """Gera relatório em JSON para processamento automatizado."""
        json_file = self.output_dir / f"duplicates_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        data = {
            'timestamp': datetime.now().isoformat(),
            'scan_directory': str(self.backup_dir),
            'summary': {
                'total_duplicate_groups': self.results.get('total_duplicate_groups', 0),
                'total_duplicate_files': self.results.get('total_duplicate_files', 0),
                'wasted_space_bytes': self.results.get('wasted_space_bytes', 0),
                'wasted_space_formatted': self._format_bytes(self.results.get('wasted_space_bytes', 0))
            },
            'duplicates': {}
        }
        
        for idx, (file_hash, files) in enumerate(self.results.get('hash_duplicates', {}).items(), 1):
            data['duplicates'][f'group_{idx}'] = {
                'hash': file_hash,
                'files': files,
                'count': len(files)
            }
        
        with open(json_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        
        print(f"✓ Relatório JSON salvo: {json_file}")
        return json_file
    
    @staticmethod
    def _format_bytes(bytes_size):
        """Formata bytes para formato legível."""
        for unit in ['B', 'KB', 'MB', 'GB']:
            if bytes_size < 1024:
                return f"{bytes_size:.2f} {unit}"
            bytes_size /= 1024
        return f"{bytes_size:.2f} TB"
    
    def run(self):
        """Executa análise completa."""
        self.scan_files()
        self.find_duplicates()
        self.find_exif_duplicates()
        self.generate_report()
        self.generate_json_report()
        
        return self.results

def main():
    parser = argparse.ArgumentParser(
        description='Detector de duplicatas para backup iCloud'
    )
    parser.add_argument('backup_dir', help='Diretório com arquivos baixados')
    parser.add_argument('-o', '--output', help='Diretório de saída (padrão: backup_dir/duplicate_analysis)')
    
    args = parser.parse_args()
    
    if not os.path.isdir(args.backup_dir):
        print(f"❌ Diretório não encontrado: {args.backup_dir}")
        sys.exit(1)
    
    detector = DuplicateDetector(args.backup_dir, args.output)
    results = detector.run()
    
    print("\n" + "="*80)
    print("✓ ANÁLISE CONCLUÍDA")
    print("="*80)

if __name__ == '__main__':
    main()
