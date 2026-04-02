#!/bin/bash
# search_by_type.sh - タイプ条件で候補ポケモンを検索
# Usage: search_by_type.sh <type1> [type2] [min_speed] [version]
# type names: Japanese (ほのお, みず, くさ, etc.)
# Output: パイプ区切りテキスト（種族値合計順）
set -euo pipefail

DB_PATH="${POKEDEX_DB:-$HOME/ghq/github.com/ushironoko/pokemon-builder/pokedex/pokedex.db}"
TYPE1="$1"
TYPE2="${2:-}"
MIN_SPEED="${3:-0}"
VERSION="${4:-scarlet_violet}"

if [ -n "$TYPE2" ]; then
  TYPE_COND="AND ((t.type1 = '$(echo "$TYPE1" | sed "s/'/''/g")' AND t.type2 = '$(echo "$TYPE2" | sed "s/'/''/g")') OR (t.type1 = '$(echo "$TYPE2" | sed "s/'/''/g")' AND t.type2 = '$(echo "$TYPE1" | sed "s/'/''/g")'))"
else
  TYPE_COND="AND (t.type1 = '$(echo "$TYPE1" | sed "s/'/''/g")' OR t.type2 = '$(echo "$TYPE1" | sed "s/'/''/g")')"
fi

sqlite3 -header -separator '|' "$DB_PATH" \
  "SELECT
    p.globalNo,
    MIN(pn.name) AS name_ja,
    t.type1, t.type2,
    s.hp, s.attack, s.defense, s.special_attack, s.special_defense, s.speed,
    (s.hp + s.attack + s.defense + s.special_attack + s.special_defense + s.speed) AS bst
  FROM pokedex p
  JOIN local_pokedex_type t ON p.globalNo = t.globalNo AND t.version = '${VERSION}'
  JOIN local_pokedex_status s ON p.globalNo = s.globalNo AND s.version = '${VERSION}'
  JOIN pokedex_name pn ON p.globalNo = pn.globalNo AND pn.language = 'jpn'
    AND COALESCE(pn.form, '') = '' AND COALESCE(pn.region, '') = ''
    AND COALESCE(pn.mega_evolution, '') = '' AND COALESCE(pn.gigantamax, '') = ''
  WHERE COALESCE(p.form, '') = ''
    AND COALESCE(p.region, '') = ''
    AND COALESCE(p.mega_evolution, '') = ''
    AND COALESCE(p.gigantamax, '') = ''
    ${TYPE_COND}
    AND s.speed >= ${MIN_SPEED}
  GROUP BY p.globalNo
  ORDER BY bst DESC
  LIMIT 20;"
