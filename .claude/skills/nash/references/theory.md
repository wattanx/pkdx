# 零和ゲーム LP の理論的背景

Nash ソルバーの基盤は **ミニマックス定理 (von Neumann 1928)** と **零和 LP 等価性 (Dantzig 1951)**、実装は **2 相 Simplex 法 + Bland's rule** (Bland 1977) による。

## 零和 2 人ゲームと LP

行列 `A ∈ ℝ^{m×n}` が行プレイヤーの利得行列。ミニマックス定理により、混合戦略 Nash 均衡は以下の LP 対で求まる。

### 主 LP (行プレイヤー)

```
max v
s.t. Σⱼ x_j · A[i, j] ≥ v  (∀i)
     Σⱼ x_j = 1,  x_j ≥ 0
```

### 双対 LP (列プレイヤー)

```
min u
s.t. Σᵢ y_i · A[i, j] ≤ u  (∀j)
     Σᵢ y_i = 1,  y_i ≥ 0
```

LP 双対性より最適値は一致: `max v = min u = v*` (ゲーム値)。

## Shift-and-Normalize による実装

負の値を含む `A` に対し 2-phase simplex を直接適用すると退化・数値不安定が起きやすい。そこで:

1. `shift = -min(A) + 1` を求め `A' = A + shift` を作る → `A' > 0` 保証
2. 次の主 LP を解く:
   ```
   max Σⱼ xⱼ
   s.t. A' x ≤ 1,  x ≥ 0
   ```
   戦略は `qⱼ = xⱼ / Σⱼ xⱼ`、ゲーム値は `v = 1/Σxⱼ − shift`
3. 双対 LP で row 戦略 `p`:
   ```
   min Σᵢ yᵢ
   s.t. A'ᵀ y ≥ 1,  y ≥ 0
   ```
   `pᵢ = yᵢ / Σy`, `v = 1/Σy − shift` (主双対で一致)

**実装**: `src/nash/solver.mbt` の `solve_zero_sum`。2 本の LP を内部で解いて戦略対を返す。

## Simplex コア (`src/nash/simplex.mbt`)

標準形 LP `max cᵀx s.t. Ax ≤ b, x ≥ 0` を以下で解く:

- **2-phase 法**: 人工変数 `z` を導入した補助問題 (`min Σz`) で初期基底を得る → 元の目的で Pivot
- **Bland's rule** (1977): pivot 候補が複数ある時、index 最小を選ぶ。退化 (縮退) 時の循環を回避
- **最大反復数**: 1000 (安全弁)。到達時は `IterationLimit` を raise

### 退化ケース

- **Infeasible**: Phase-1 の人工変数が最適時に 0 でない → 実行不可能
- **Unbounded**: pivot 列の全エントリが ≤ 0 → 目的関数を無限に増やせる

これらは `SimplexStatus::Infeasible` / `Unbounded` として返される。

## 反復学習ソルバー (`src/nash/fictitious.mbt`)

大規模行列で Simplex の正確解が不要な場合に使用。

### Fictitious Play (Brown 1951 / Robinson 1951)

各回で両プレイヤーが相手の経験頻度に対する最良応答を打ち、頻度を更新する。零和ゲームで時間平均戦略が Nash に収束することが Robinson により証明済 (Annals of Math 54)。

- **特徴**: 実装が単純、メモリ軽量。ただし収束率は `O(1/√T)` と遅い
- **用途**: デバッグ、Simplex の独立検証、退化で LP が失敗した時のフォールバック

### MWU (Multiplicative Weights Update, Freund & Schapire 1999)

重みを指数関数的に更新する。`O(√(log n / T))` の regret bound。payoff スケール依存なので内部で `[0, 1]` に正規化。

- **推奨 η**: `√(log(max(m, n)) / T)` (理論最適)
- **早期停止**: exploitability が閾値以下なら打ち切り可能 (現実装では未サポート)

## 数値公差

| 場所 | 閾値 | 理由 |
|---|---|---|
| exploitability 判定 | 1e-6 | simplex の丸め誤差 |
| 混合戦略 support | 1e-6 | 純戦略で ε 未満は "mass なし" |
| usage 正規化 | 1e-6 | 浮動小数和の累積誤差 |
| power 比較 (monocycle) | 1e-12 | 整数同値判定 |
| 線形系の det | 1e-12 | 特異判定 |

## 参考文献

- Bland (1977) "New finite pivoting rules", DOI:10.1287/moor.2.2.103
- Bertsimas & Tsitsiklis *Introduction to Linear Optimization* §3.3–3.5
- Chvátal *Linear Programming* Ch.2, 3
- Dantzig (1951) Cowles Monograph 13 Ch.XX
- Robinson (1951) Annals of Math 54
- Freund & Schapire (1999) *Games Econ. Behav.* 29, DOI:10.1006/game.1999.0738
