"""Comprueba que cada cita literal de assets/conocimiento/base.json aparece en la página
indicada del documento original.

Uso (los .txt son el texto extraído de cada PDF, con una línea "=== PAGINA n ===" al
empezar cada página; las fuentes y sus enlaces están en la sección "fuentes" del JSON):

    python3 -I tool/verificar_conocimiento.py fhia2017=fhia.txt lasalle2022=lasalle.txt ica2012=ica.txt

Sale con código 1 si alguna cita no se encuentra. No inventa ni corrige nada: solo compara.
"""
import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BASE = RAIZ / "assets" / "conocimiento" / "base.json"


def normalizar(t: str) -> str:
    t = t.replace("­", "")
    t = re.sub(r"-\n", "", t)  # palabra partida al final de la línea
    return re.sub(r"\s+", " ", t).strip()


PALABRAS_NUMERO = {
    "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
    "nueve": 9, "diez": 10, "quince": 15, "veinte": 20, "cien": 100,
}


def numeros(t: str) -> set[float]:
    """Números de un texto: los escritos con cifras (6,5 y 6.5 son lo mismo) y los escritos con
    letras (dos, cien...). Sirve para comprobar que ninguna cifra del resumen está inventada."""
    t = normalizar(t).lower()
    cifras = {float(m.replace(",", ".")) for m in re.findall(r"\d+(?:[.,]\d+)?", t)}
    letras = {PALABRAS_NUMERO[w] for w in re.findall(r"[a-záéíóúñ]+", t) if w in PALABRAS_NUMERO}
    return cifras | {float(n) for n in letras}


def cargar_paginas(ruta: str) -> dict[int, str]:
    texto = Path(ruta).read_text(encoding="utf-8")
    trozos = re.split(r"=== PAGINA (\d+) ===", texto)
    return {int(trozos[i]): normalizar(trozos[i + 1]) for i in range(1, len(trozos) - 1, 2)}


def main() -> int:
    docs = {}
    for arg in sys.argv[1:]:
        clave, _, ruta = arg.partition("=")
        docs[clave] = cargar_paginas(ruta)
    base = json.loads(BASE.read_text(encoding="utf-8"))

    revisadas = fallos = 0
    elementos = [(f["id"], f["fuente_id"], f["citas"], f["texto"], f["fuente"], f.get("numeros_app", [])) for f in base["fragmentos"]]
    elementos += [("glosario:" + g["termino"], g["fuente_id"], g["citas"], g["definicion"], g["fuente"], []) for g in base["glosario"]]
    for ident, fuente_id, citas, texto, fuente, de_la_app in elementos:
        # Las cifras del resumen deben salir de las páginas que cita (las de las citas y las de "fuente").
        if fuente_id in docs:
            paginas_citadas = {c["p"] for c in citas} | {int(n) for n in re.findall(r"p\. (\d+)", fuente)}
            respaldo = set().union(*(numeros(docs[fuente_id].get(p, "")) for p in paginas_citadas))
            for n in sorted(numeros(texto) - respaldo - {float(x) for x in de_la_app}):
                print(f"NÚMERO SIN RESPALDO {ident}: {n:g} no aparece en las páginas citadas")
                fallos += 1
        for c in citas:
            revisadas += 1
            paginas = docs.get(fuente_id)
            if paginas is None:
                print(f"SIN TEXTO  {ident}: no se dio el documento '{fuente_id}'")
                fallos += 1
            elif normalizar(c["t"]) not in paginas.get(c["p"], ""):
                print(f"NO APARECE {ident} (p. {c['p']}): {c['t'][:90]}")
                fallos += 1
    print(f"citas revisadas: {revisadas} | no encontradas: {fallos}")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
