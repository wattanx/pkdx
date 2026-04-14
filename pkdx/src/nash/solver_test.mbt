///|
fn strategies_close(
  s1 : MixedStrategy,
  s2 : MixedStrategy,
  tol : Double,
) -> Bool {
  if s1.len() != s2.len() {
    return false
  }
  for i in 0..<s1.len() {
    if (s1.at(i) - s2.at(i)).abs() > tol {
      return false
    }
  }
  true
}

///|
fn matrix(data : Array[Array[Double]]) -> FiniteMatrix {
  FiniteMatrix::new(data).unwrap()
}

///|
test "rps_equilibrium_uniform" {
  let a = matrix([[0.0, -1.0, 1.0], [1.0, 0.0, -1.0], [-1.0, 1.0, 0.0]])
  let uniform = MixedStrategy::uniform(3)
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true(value.abs() < 1.0e-7)
      assert_true(strategies_close(row_strategy, uniform, 1.0e-7))
      assert_true(strategies_close(col_strategy, uniform, 1.0e-7))
    }
    _ => assert_true(false)
  }
}

///|
test "matching_pennies_mixed" {
  let a = matrix([[1.0, -1.0], [-1.0, 1.0]])
  let uniform = MixedStrategy::uniform(2)
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true(value.abs() < 1.0e-7)
      assert_true(strategies_close(row_strategy, uniform, 1.0e-7))
      assert_true(strategies_close(col_strategy, uniform, 1.0e-7))
    }
    _ => assert_true(false)
  }
}

///|
test "saddle_point_pure_equilibrium" {
  // Row 0 has row-min = 2 at col 0. Col 0 has col-max = 2 at row 0. Saddle at (0,0).
  let a = matrix([[2.0, 3.0, 5.0], [1.0, 2.0, 4.0], [0.0, 1.0, 3.0]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true((value - 2.0).abs() < 1.0e-7)
      assert_true((row_strategy.at(0) - 1.0).abs() < 1.0e-7)
      assert_true((col_strategy.at(0) - 1.0).abs() < 1.0e-7)
    }
    _ => assert_true(false)
  }
}

///|
test "2x2_mixed_closed_form" {
  // A = [[a,b],[c,d]] mixed equilibrium:
  //   p* = (d - c) / (a - b - c + d), q* = (d - b) / (a - b - c + d)
  //   v = (a d - b c) / (a - b - c + d)
  let a_val = 3.0
  let b_val = 1.0
  let c_val = 2.0
  let d_val = 4.0
  let denom = a_val - b_val - c_val + d_val // 4.0
  let expected_p0 = (d_val - c_val) / denom // 0.5
  let expected_q0 = (d_val - b_val) / denom // 0.75
  let expected_v = (a_val * d_val - b_val * c_val) / denom // 2.5
  let a = matrix([[a_val, b_val], [c_val, d_val]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true((value - expected_v).abs() < 1.0e-7)
      assert_true((row_strategy.at(0) - expected_p0).abs() < 1.0e-7)
      assert_true((col_strategy.at(0) - expected_q0).abs() < 1.0e-7)
    }
    _ => assert_true(false)
  }
}

///|
test "minimax_equals_maximin" {
  // For any zero-sum game, v(A) = -v(-Aᵀ). Verify by swapping row/col roles.
  let a = matrix([[3.0, 1.0, 4.0], [1.0, 5.0, 9.0], [2.0, 6.0, 5.0]])
  // Opponent game: -Aᵀ as row-player matrix for the column player.
  let neg_at = Array::make(3, ([] : Array[Double]))
  for j in 0..<3 {
    let row = Array::make(3, 0.0)
    for i in 0..<3 {
      row[i] = -a.at(i, j)
    }
    neg_at[j] = row
  }
  let a_opp = matrix(neg_at)
  match (solve_zero_sum(a), solve_zero_sum(a_opp)) {
    (Optimal(value=v1, ..), Optimal(value=v2, ..)) =>
      assert_true((v1 + v2).abs() < 1.0e-7)
    _ => assert_true(false)
  }
}

///|
test "value_invariant_under_constant_shift" {
  let a = matrix([[2.0, -1.0, 3.0], [0.0, 4.0, -2.0], [1.0, 2.0, 0.0]])
  let shift = 7.5
  let a_shifted_data = Array::make(3, ([] : Array[Double]))
  for r in 0..<3 {
    let row = Array::make(3, 0.0)
    for c in 0..<3 {
      row[c] = a.at(r, c) + shift
    }
    a_shifted_data[r] = row
  }
  let a_shifted = matrix(a_shifted_data)
  match (solve_zero_sum(a), solve_zero_sum(a_shifted)) {
    (
      Optimal(value=v1, row_strategy=p1, col_strategy=q1),
      Optimal(value=v2, row_strategy=p2, col_strategy=q2),
    ) => {
      assert_true((v2 - v1 - shift).abs() < 1.0e-7)
      assert_true(strategies_close(p1, p2, 1.0e-7))
      assert_true(strategies_close(q1, q2, 1.0e-7))
    }
    _ => assert_true(false)
  }
}

///|
test "value_scales_linearly_in_payoff" {
  let a = matrix([[1.0, -1.0], [-1.0, 1.0]])
  let k = 5.0
  let ak_data = Array::make(2, ([] : Array[Double]))
  for r in 0..<2 {
    let row = Array::make(2, 0.0)
    for c in 0..<2 {
      row[c] = a.at(r, c) * k
    }
    ak_data[r] = row
  }
  let ak = matrix(ak_data)
  match (solve_zero_sum(a), solve_zero_sum(ak)) {
    (Optimal(value=v1, ..), Optimal(value=v2, ..)) =>
      assert_true((v2 - v1 * k).abs() < 1.0e-7)
    _ => assert_true(false)
  }
}

///|
test "dominated_row_has_zero_probability" {
  // Row 2 is strictly dominated by row 0: 0 ≤ 2, 0 ≤ 3.
  let a = matrix([[2.0, 3.0], [1.0, 4.0], [0.0, 0.0]])
  match solve_zero_sum(a) {
    Optimal(row_strategy~, ..) => assert_true(row_strategy.at(2) < 1.0e-7)
    _ => assert_true(false)
  }
}

///|
test "negative_entries_handled_without_big_m" {
  // All-negative matrix. The shift-and-normalize technique must handle it.
  let a = matrix([[-1.0, -2.0], [-3.0, -1.0]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      // Sanity: value should be in the convex hull of A entries, i.e. [-3, -1]
      assert_true(value >= -3.0 - 1.0e-7 && value <= -1.0 + 1.0e-7)
      // Strategies are valid distributions
      let sp = row_strategy.at(0) + row_strategy.at(1)
      let sq = col_strategy.at(0) + col_strategy.at(1)
      assert_true((sp - 1.0).abs() < 1.0e-7)
      assert_true((sq - 1.0).abs() < 1.0e-7)
    }
    _ => assert_true(false)
  }
}

///|
test "shapley_3x3_degenerate_game" {
  // Degenerate 3×3 with row-0 and row-1 identical in two columns — Lemke–Howson
  // explores multiple edges. Bland-based simplex must still terminate and
  // return some valid equilibrium (not necessarily unique).
  let a = matrix([[0.0, 0.0, 1.0], [0.0, 0.0, -1.0], [-1.0, 1.0, 0.0]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      // Exploitability ≤ 1e-6 certifies equilibrium without pinning the vector.
      let expl = exploitability(a, row_strategy, col_strategy)
      assert_true(expl.abs() < 1.0e-6)
      // Value is the Nash value regardless of which equilibrium is selected.
      ignore_value(value)
    }
    _ => assert_true(false)
  }
}

///|
fn ignore_value(_v : Double) -> Unit {
  ()
}

///|
test "janken_reproduces_monocycle_nash_baseline" {
  // Reference: monocycle_nash baseline/janken_solve — the janken (RPS) matrix
  // from the characters form with v vectors forming an equilateral triangle.
  // Value 0, uniform strategies, exploitability 0.
  let a = matrix([[0.0, -1.0, 1.0], [1.0, 0.0, -1.0], [-1.0, 1.0, 0.0]])
  match solve_zero_sum(a) {
    Optimal(value~, row_strategy~, col_strategy~) => {
      assert_true(value.abs() < 1.0e-7)
      let expl = exploitability(a, row_strategy, col_strategy)
      assert_true(expl.abs() < 1.0e-6)
      // Support uniformity
      for i in 0..<3 {
        assert_true((row_strategy.at(i) - 1.0 / 3.0).abs() < 1.0e-6)
        assert_true((col_strategy.at(i) - 1.0 / 3.0).abs() < 1.0e-6)
      }
    }
    _ => assert_true(false)
  }
}
