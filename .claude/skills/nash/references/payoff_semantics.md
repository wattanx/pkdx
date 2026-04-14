# PayoffModel 仕様と選択基準

`pkdx select` や `pkdx nash solve` (characters 形式以外) で利得を damage 計算から作る際の選択肢。実装は `src/payoff/from_damage.mbt` (`winrate`, `best1v1_winrate`, `nash_responses_winrate`)。

## 共通仕様

- 返り値は `[0, 1]` の winrate。最終行列 `A[i, j] = 2·winrate(i, j) − 1 ∈ [-1, +1]`
- `A[i, j] + A[j, i] = 0` が厳密に成立 (定義から自動保証)
- 対角は常に 0 (同一の自己対戦 → 速度タイ → 0.5 → payoff 0)

## Best1v1 (既定)

### 計算アルゴリズム

```
ta = min over a.moves of (defender_hp / avg_damage(a → b using move))
tb = min over b.moves of (attacker_hp / avg_damage(b → a using move))

if ta < tb:       winrate = 1.0
elif ta > tb:     winrate = 0.0
elif ta = ∞:      winrate = 0.5   # 両者とも通らない
elif a.spe > b.spe: winrate = 1.0
elif a.spe < b.spe: winrate = 0.0
else:             winrate = 0.5
```

- `avg_damage`: 16-roll の算術平均 (immune は 0)
- `turns_to_ko`: `defender_hp / avg_damage`、ダメージ 0 なら `+∞`

### 意図と限界

**意図**: 速くて分かりやすく、多くの対面で「結局これで勝つか負けるか」の近似として機能する。

**限界**:
- 交代・状態異常・フィールド等を無視
- 耐久技・回復技を考慮しない (ダメージ 0 なら勝てない扱い)
- 混合戦略 (技選択のランダム化) を許容しない

**使いどころ**: 使用率ベースのメタ分析、選出最適化の高速計算 (6v6 → 20×20 行列が数ミリ秒)。

## NashResponses

### 計算アルゴリズム

各対面 (i, j) について、a の技 × b の技の内部 |moves_a| × |moves_b| 行列を作り、ゼロ和 Nash を解いた値を `A[i, j]` とする:

```
inner[k, l] = encode(turns_to_ko(a, b, a.moves[k]), turns_to_ko(b, a, b.moves[l]), speed)
            ∈ {-1, 0, +1}
A[i, j] = (Nash_value(inner) + 1) / 2 - 0.5   # rescaled
```

### 意図と限界

**意図**: 技選択の commitment problem を明示的にモデル化。「A は強い技だが B のカウンターに弱い」といった循環が内部に含まれる場合、単純な最良応答選択 (Best1v1) では得られない戦略的価値を計算できる。

**限界**:
- 計算量: 6v6 で 36 小 Nash × 20 選出対 = 非自明に重い
- 技の外にある動作 (交代、持ち物発動、テラスタル) は依然考慮しない
- 内部 Nash の判定も ±1/0 の離散化 → 中間 (ダメージ量の僅差) は粗い

**使いどころ**: 行列内に循環が明らかな構成 (例: みず vs くさ vs ほのお 型の 3 タイプ技)、技選択が勝敗を決する特殊な構築。

## 比較表

| 観点 | Best1v1 | NashResponses |
|---|---|---|
| 計算量 (6v6 single) | 6×6 ≈ 36 damage calc | 6×6 × 4×4 + 20×20 = 600+ damage calc + 400 small Nash |
| 技選択のモデル化 | 最大ダメージ固定 | 同時行動の Nash |
| 循環への対応 | 外側のみ | 内側も表現 |
| デバッグ性 | 高い (手計算可) | 中 (内部行列を覗く必要) |
| 推奨場面 | 通常の選出最適 | 技循環が議論の中心 |

## CLI フラグ

```bash
pkdx select --payoff-model best1v1       # デフォルト
pkdx select --payoff-model nash_responses
```

(注: 現バージョンでは `payoff_model` は JSON 入力の `"payoff_model"` フィールドで指定。CLI フラグは未実装。)

## 実装の検証

- `src/payoff/from_damage_test.mbt` に両モデルの単体テスト
- `nash_responses_matches_inner_game_value`: 1 手 vs 1 手の退化ケースで Best1v1 と一致することを確認 (内部 1×1 の Nash 値 = 単一セル値 = Best1v1 結果)

## 将来拡張

`PayoffModel` は enum なので、以下の variant を追加して比較可能:

- `MonteCarloSim(trials: Int, seed: UInt64)` — サイコロ込みシミュレーション
- `SwitchingGame(turn_limit: Int)` — 交代を含む n-turn 展開
- `ChampionsSP(stat_system: StatSystem)` — SP 合計 66 制約下の最適化

追加時は `from_damage.mbt` の `winrate` の match に分岐を足すのみ。既存テストは `payoff_model_enum_exhaustive` で網羅性をチェックする。
