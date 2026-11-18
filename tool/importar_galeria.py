"""Separa la galería de referencia (carpeta descargada) en dos partes del repositorio:

  backend/referencias/   fotos de REFERENCIA (las que el servidor puede mandar a la IA como ejemplos)
  evaluacion/galeria/    fotos de PRUEBA (solo sirven para medir el acierto; nunca se mandan como ejemplo)

Uso:  python3 -I tool/importar_galeria.py RUTA/galeria_referencia_cacao

Copia las fotos y escribe un manifest.json en cada carpeta con los datos de fuente, autores, DOI y
licencia de cada foto (los del manifest original). No descarga nada y no ejecuta nada de la carpeta.
"""
import json
import shutil
import sys
from pathlib import Path

CARPETA = {'corte': 'cortes', 'mazorca': 'mazorcas'}


def main(origen: Path) -> int:
    manifest = json.loads((origen / 'manifest.json').read_text(encoding='utf-8'))
    destinos = {'referencia': Path('backend/referencias'), 'prueba': Path('evaluacion/galeria')}
    salida = {'referencia': [], 'prueba': []}
    for d in destinos.values():
        if d.exists():
            shutil.rmtree(d)
    for e in manifest:
        rol = e['rol']
        if rol not in destinos:
            print(f'rol desconocido: {rol}', file=sys.stderr)
            return 1
        fuente = origen / e['archivo']
        if not fuente.is_file() or fuente.suffix.lower() != '.jpg':
            print(f'falta o no es .jpg: {e["archivo"]}', file=sys.stderr)
            return 1
        rel = Path(CARPETA[e['modo']]) / e['clase_original'] / fuente.name
        destino = destinos[rol] / rel
        destino.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fuente, destino)
        nuevo = dict(e)
        nuevo['archivo'] = rel.as_posix()
        nuevo.pop('rol', None)
        salida[rol].append(nuevo)
    for rol, d in destinos.items():
        (d / 'manifest.json').write_text(json.dumps(salida[rol], ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'{d}: {len(salida[rol])} fotos')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1])))
