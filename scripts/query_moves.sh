#!/bin/bash
# query_moves.sh - ポケモンが覚える技の一覧を取得
# Usage: query_moves.sh <globalNo> [version]
# Output: パイプ区切りテキスト（レベル技+TM技の統合リスト）
# Note: waza系テーブルのversionはMixed Case (e.g., Scarlet_Violet)
set -euo pipefail

DB_PATH="${POKEDEX_DB:-$HOME/ghq/github.com/ushironoko/pokemon-builder/pokedex/pokedex.db}"
GLOBAL_NO="$1"
VERSION_LOWER="${2:-scarlet_violet}"

# waza系テーブル用にMixed Caseに変換
# scarlet_violet → Scarlet_Violet, legendsza → LegendsZA
case "$VERSION_LOWER" in
  scarlet_violet) VERSION_WAZA="Scarlet_Violet" ;;
  legendsza)      VERSION_WAZA="LegendsZA" ;;
  sword_shield)   VERSION_WAZA="sword_shield" ;;
  *)              VERSION_WAZA="$VERSION_LOWER" ;;
esac

sqlite3 -header -separator '|' "$DB_PATH" \
  "SELECT DISTINCT wl.name AS move_name, w.type, w.category, w.power, w.accuracy, w.pp, pw.conditions AS learn_method
  FROM local_pokedex_waza pw
  JOIN local_waza w ON pw.waza = w.waza AND w.version = '${VERSION_WAZA}'
  JOIN local_waza_language wl ON pw.waza = wl.waza AND wl.version = '${VERSION_WAZA}' AND wl.language = 'jpn'
  WHERE pw.globalNo = '${GLOBAL_NO}' AND pw.version = '${VERSION_WAZA}'
  UNION
  SELECT DISTINCT wl.name AS move_name, w.type, w.category, w.power, w.accuracy, w.pp, 'TM' AS learn_method
  FROM local_pokedex_waza_machine pm
  JOIN local_waza_machine wm ON pm.machine_no = wm.waza AND wm.version = '${VERSION_WAZA}'
  JOIN local_waza w ON wm.machine_no = w.waza AND w.version = '${VERSION_WAZA}'
  JOIN local_waza_language wl ON w.waza = wl.waza AND wl.version = '${VERSION_WAZA}' AND wl.language = 'jpn'
  WHERE pm.globalNo = '${GLOBAL_NO}' AND pm.version = '${VERSION_WAZA}'
    AND COALESCE(pm.form, '') = '' AND COALESCE(pm.region, '') = ''
  ORDER BY power DESC;"
