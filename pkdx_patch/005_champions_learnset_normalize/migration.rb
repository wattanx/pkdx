# 005_champions_learnset_normalize — Champions 学習技を別テーブルに正規化し、
# yakkun スクレイピング由来の「没収技」を state='inactive' でマークする。
#
# Background: 004 migration で挿入した local_pokedex_waza (version='Champions') には
# yakkun の没収技テーブルが混入していた (詳細は CLAUDE.md / PR description 参照)。
# ここでは新テーブル champions_learnset に引っ越しつつ、タイプ順アルゴリズムで
# 没収技を検出して state='inactive' にする。
#
# apply.rb から eval される。db (SQLite3::Database) と patch_dir が利用可能。

# --- スキーマ: 存在しなければ作成 ---
db.execute <<~SQL
  CREATE TABLE IF NOT EXISTS champions_learnset (
    id             TEXT,
    globalNo       TEXT,
    form           TEXT,
    region         TEXT,
    mega_evolution TEXT,
    gigantamax     TEXT,
    pokedex        TEXT,
    conditions     TEXT,
    waza           TEXT,
    state          TEXT NOT NULL DEFAULT 'active'
                   CHECK (state IN ('active', 'inactive'))
  )
SQL

# --- 技 → タイプ マップ (Champions 版) ---
type_map = {}
db.execute("SELECT waza, type FROM local_waza WHERE version='Champions'") do |row|
  type_map[row[0]] = row[1]
end

# --- 既存 Champions 行を順序維持で読み出し ---
# rowid 順 = 挿入順 = yakkun ページ上のテーブル内順序
rows = db.execute(<<~SQL)
  SELECT id, globalNo, form, region, mega_evolution, gigantamax,
         pokedex, conditions, waza
  FROM local_pokedex_waza
  WHERE version = 'Champions'
  ORDER BY rowid
SQL

if rows.empty?
  puts '    No Champions rows in local_pokedex_waza — assuming already normalized.'
else
  # --- グループ化: (globalNo, form, region, mega_evolution, gigantamax) ---
  # Ruby の Hash は挿入順を保持するので、グループ内の順序も rowid 順が維持される
  groups = {}
  rows.each do |r|
    key = r[1..5]  # globalNo, form, region, mega_evolution, gigantamax
    (groups[key] ||= []) << r
  end

  # --- 没収技検出: 「一度閉じたタイプが再出現した時点から没収」 ---
  # yakkun の本表はタイプ連続ブロック構造。没収表はそれに続く別テーブル。
  active_count = 0
  inactive_count = 0
  unknown_type_count = 0

  groups.each_value do |items|
    seen_closed = {}
    current_type = nil
    cutoff = nil

    items.each_with_index do |r, idx|
      waza = r[8]
      t = type_map[waza]
      if t.nil?
        unknown_type_count += 1
        next
      end
      if current_type.nil?
        current_type = t
      elsif t != current_type
        seen_closed[current_type] = true
        current_type = t
        if seen_closed[t]
          cutoff = idx
          break
        end
      end
    end

    items.each_with_index do |r, idx|
      state = (cutoff && idx >= cutoff) ? 'inactive' : 'active'
      state == 'active' ? (active_count += 1) : (inactive_count += 1)
      db.execute(
        <<~SQL,
          INSERT INTO champions_learnset
            (id, globalNo, form, region, mega_evolution, gigantamax,
             pokedex, conditions, waza, state)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL
        [r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], state]
      )
    end
  end

  # --- 引っ越し完了後、元データを削除 ---
  db.execute("DELETE FROM local_pokedex_waza WHERE version='Champions'")

  puts "    Migrated #{active_count + inactive_count} rows " \
       "(active=#{active_count}, inactive=#{inactive_count}, " \
       "unknown_type=#{unknown_type_count})"
end
