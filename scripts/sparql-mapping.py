#!/usr/bin/env python3
"""Genera un mapping YARRRML para execute_sparql sobre un parquet de tripletas.

Uso: scripts/sparql-mapping.py <parquet|url> <vista> [salida.yml]
  scripts/sparql-mapping.py http://localhost:9000/test/wiki_pos.parquet wiki_pos mapping-pos.yml

El parquet debe tener las columnas s, p, o, kind ('iri' | 'lit'), datatype y lang (NULL si no aplica).
<vista> es el nombre con que el hook expone el parquet (el nombre del archivo sin .parquet).

En YARRRML el datatype y el idioma de un objeto son constantes, así que se emite un triples map por cada
combinación (kind, datatype, lang) presente en los datos. Cada uno usa una fuente `query:` que filtra la vista;
el traductor la inlinea como subconsulta, así que no hace falta crear tablas y el mapping sobrevive a un F5.
"""
import json
import subprocess
import sys


def sql_string(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__.strip().splitlines()[2])
    parquet, view = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) == 4 else f'mapping-{view}.yml'

    rows = json.loads(subprocess.check_output([
        'duckdb', '-json', '-c',
        f'SELECT kind, datatype, lang, count(*) n FROM read_parquet({sql_string(parquet)}) GROUP BY ALL ORDER BY n DESC',
    ]))

    maps = []
    for r in rows:
        kind, dt, lang = r['kind'], r['datatype'], r['lang']
        if kind == 'iri':
            name, where, obj = 'iri', "kind = 'iri'", '[$(p), $(o)~iri]'
        elif lang:
            name, where, obj = f'lang_{lang}', f'lang = {sql_string(lang)}', f'[$(p), $(o), {lang}~lang]'
        elif dt:
            name = 'dt_' + dt.rsplit('#', 1)[-1].rsplit('/', 1)[-1]
            where, obj = f'datatype = {sql_string(dt)}', f'[$(p), $(o), {dt}]'
        else:
            name, where, obj = 'plain', "kind = 'lit' AND datatype IS NULL AND lang IS NULL", '[$(p), $(o)]'
        maps.append((name, f'SELECT s, p, o FROM {view} WHERE {where}', obj, r['n']))

    with open(out, 'w') as f:
        f.write('mappings:\n')
        for name, sql, obj, _ in maps:
            f.write(f'  {name}:\n    sources:\n      - query: "{sql}"\n    s: $(s)\n    po:\n      - {obj}\n')
    for name, _, _, n in maps:
        print(f'{name:20s} {n:>12,}')
    print(f'{out}: {len(maps)} triples maps')


if __name__ == '__main__':
    main()
