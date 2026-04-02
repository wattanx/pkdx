# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ポケモン対戦構築支援リポジトリ。Claude Codeのスキル（`.claude/skills/pokemon-builder/`）として動作し、6体構築・3体選出のシングルバトル向けチームビルドを対話的にガイドする。コードベースは持たず、SQLiteデータベースへのシェルスクリプトクエリとスキル定義で構成される。

## Setup

```bash
git submodule update --init          # pokedex サブモジュール取得
cd pokedex && ruby tools/import_db.rb # pokedex.db 生成
```

`pokedex.db` が存在しないとスキルは動作しない。

## Architecture

```
.claude/skills/pokemon-builder/
  SKILL.md              # スキル本体（Phase 0-8 の対話フロー定義）
  references/
    format_rules.md     # メカニクス定義（メガ/ダイマ/Z/テラスタル）
    stat_thresholds.md  # 種族値ベンチマーク・素早さティア
  scripts/
    query_pokemon.sh    # ポケモン名 → 基本データ（globalNo, タイプ, 種族値, 特性）
    query_moves.sh      # globalNo → 覚える技一覧（レベル技+TM統合）
    search_by_type.sh   # タイプ条件 → 候補ポケモン検索（BST順）
pokedex/                # git submodule (towakey/pokedex)
  pokedex.db            # SQLiteデータベース（生成が必要）
  type/type.json        # タイプ相性表
  er.md                 # DB ER図
```

## Database Notes

- `pokedex.db` のテーブル群は `globalNo` + フォーム識別カラム（`form`, `region`, `mega_evolution`, `gigantamax`）で結合する
- 通常フォームの取得には `COALESCE(form, '') = ''` 等の条件が必要（NULL/空文字が混在）
- `local_pokedex_*` テーブルの `version` は小文字スネーク（`scarlet_violet`）
- `local_waza*` / `local_pokedex_waza*` テーブルの `version` は Mixed Case（`Scarlet_Violet`）— スクリプト内で変換している
- タイプ名は日本語（`ほのお`, `みず` 等）

## Script Usage

すべてのスクリプトは `POKEDEX_DB` 環境変数またはリポジトリルートからの自動解決で DB パスを決定する。

```bash
# ポケモン検索（日本語名 or 英語名）
bash .claude/skills/pokemon-builder/scripts/query_pokemon.sh "ガブリアス" "scarlet_violet"

# 技一覧取得（globalNoを指定）
bash .claude/skills/pokemon-builder/scripts/query_moves.sh "445" "scarlet_violet"

# タイプ検索（タイプ名は日本語、最低素早さ指定可）
bash .claude/skills/pokemon-builder/scripts/search_by_type.sh "ドラゴン" "" "100" "scarlet_violet"
```

## Skill Flow

スキルは Phase 0（初期化）→ Phase 8（レポート出力）の順に進行する。各フェーズ終了時に `=== Team State ===` ブロックを出力し、コンテキスト圧縮後も状態を復元可能にする。最終成果物は `{軸ポケモン名}-build-{YYYY-MM-DD}.md` として出力される。
