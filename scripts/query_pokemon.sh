#!/bin/bash
# query_pokemon.sh - ポケモン名から基本データを取得
# Usage: query_pokemon.sh <name> [version]
# Output: パイプ区切りテキスト（globalNo含む）
# version: scarlet_violet (default), legendsza, sword_shield, etc.
set -euo pipefail

DB_PATH="${POKEDEX_DB:-$HOME/ghq/github.com/ushironoko/pokemon-builder/pokedex/pokedex.db}"
NAME="$1"
VERSION="${2:-scarlet_violet}"

# DB内のNULL/空文字の混在に対応するためCOALESCEで統一
sqlite3 -header -separator '|' "$DB_PATH" \
  "SELECT
    pn.globalNo,
    pn.name AS name_ja,
    pne.name AS name_en,
    t.type1, t.type2,
    s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed,
    (s.hp + s.attack + s.defense + s.special_attack + s.special_defense + s.speed) AS bst,
    a.ability1, a.ability2, a.dream_ability
  FROM pokedex_name pn
  JOIN pokedex_name pne ON pn.globalNo = pne.globalNo
    AND pne.language = 'eng'
    AND COALESCE(pne.form, '') = '' AND COALESCE(pne.region, '') = ''
    AND COALESCE(pne.mega_evolution, '') = '' AND COALESCE(pne.gigantamax, '') = ''
  JOIN local_pokedex_type t ON pn.globalNo = t.globalNo
    AND t.version = '${VERSION}'
  JOIN local_pokedex_status s ON pn.globalNo = s.globalNo
    AND s.version = '${VERSION}'
  JOIN local_pokedex_ability a ON pn.globalNo = a.globalNo
    AND a.version = '${VERSION}'
  WHERE COALESCE(pn.form, '') = ''
    AND COALESCE(pn.region, '') = ''
    AND COALESCE(pn.mega_evolution, '') = ''
    AND COALESCE(pn.gigantamax, '') = ''
    AND (
      (pn.language = 'jpn' AND pn.name = '$(echo "$NAME" | sed "s/'/''/g")')
      OR (pn.language = 'eng' AND LOWER(pn.name) = LOWER('$(echo "$NAME" | sed "s/'/''/g")'))
    )
  LIMIT 1;"
