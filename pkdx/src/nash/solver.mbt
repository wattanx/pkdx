///|
/// Public API for zero-sum two-player matrix game Nash equilibrium.
///
/// Reduces the game to an LP via the standard shift-and-normalize technique
/// (Dantzig 1951): shift the payoff matrix so all entries are positive, solve
/// the primal LP `min Σyᵢ s.t. A'ᵀy ≥ 1, y ≥ 0` and the dual LP
/// `max Σxⱼ s.t. A'x ≤ 1, x ≥ 0`, then recover mixed strategies via
/// `pᵢ = yᵢ / Σy`, `qⱼ = xⱼ / Σx`, and value `v = 1/Σy − shift`.
///
/// Reference: Ferguson, *Game Theory* Part II §4.

///|
pub suberror SolverError {
  /// Propagated from the underlying simplex solver.
  SimplexFailure(SimplexError)
  /// Zero-sum LP returned Infeasible/Unbounded unexpectedly (should never
  /// occur for a finite matrix game; indicates a numerical issue).
  InconsistentGame(String)
} derive(Show)

///|
/// Find the minimum entry of a FiniteMatrix.
fn min_entry(matrix : FiniteMatrix) -> Double {
  let mut m = matrix.at(0, 0)
  for r in 0..<matrix.rows() {
    for c in 0..<matrix.cols() {
      let v = matrix.at(r, c)
      if v < m {
        m = v
      }
    }
  }
  m
}

///|
/// Solve the zero-sum game for the row player's mixed strategy by LP.
///
/// Input: positive-entry matrix A' (m × n).
/// Output: length-m vector y ≥ 0 with Σy = S, where 1/S is the shifted value.
/// The primal LP is `min Σyᵢ s.t. A'ᵀy ≥ 1`, encoded as `max −Σyᵢ s.t. −A'ᵀy ≤ −1`.
fn solve_row_lp(
  shifted : Array[Array[Double]],
  rows : Int,
  cols : Int,
) -> Array[Double] raise SolverError {
  // c_lp: length rows, all -1 (maximize -Σy)
  let c_lp = Array::make(rows, -1.0)
  // a_lp: cols × rows matrix, a_lp[j][i] = -shifted[i][j]
  let a_lp = Array::make(cols, ([] : Array[Double]))
  for j in 0..<cols {
    let row = Array::make(rows, 0.0)
    for i in 0..<rows {
      row[i] = -shifted[i][j]
    }
    a_lp[j] = row
  }
  let b_lp = Array::make(cols, -1.0)
  let problem = LpProblem::{ c: c_lp, a: a_lp, b: b_lp }
  let status = solve_lp(problem) catch { err => raise SimplexFailure(err) }
  match status {
    SimplexStatus::Optimal(x~, ..) => x
    SimplexStatus::Infeasible => raise InconsistentGame("row LP infeasible")
    SimplexStatus::Unbounded => raise InconsistentGame("row LP unbounded")
  }
}

///|
/// Solve the zero-sum game for the column player's mixed strategy by LP.
///
/// Input: positive-entry matrix A' (m × n).
/// Output: length-n vector x ≥ 0 with Σx = S = 1/shifted_value.
/// LP: `max Σxⱼ s.t. A'x ≤ 1, x ≥ 0`.
fn solve_col_lp(
  shifted : Array[Array[Double]],
  rows : Int,
  cols : Int,
) -> Array[Double] raise SolverError {
  let c_lp = Array::make(cols, 1.0)
  // a_lp: rows × cols, direct copy of shifted
  let a_lp = Array::make(rows, ([] : Array[Double]))
  for i in 0..<rows {
    a_lp[i] = shifted[i].copy()
  }
  let b_lp = Array::make(rows, 1.0)
  let problem = LpProblem::{ c: c_lp, a: a_lp, b: b_lp }
  let status = solve_lp(problem) catch { err => raise SimplexFailure(err) }
  match status {
    SimplexStatus::Optimal(x~, ..) => x
    SimplexStatus::Infeasible => raise InconsistentGame("col LP infeasible")
    SimplexStatus::Unbounded => raise InconsistentGame("col LP unbounded")
  }
}

///|
/// Compute the Nash equilibrium of a finite two-player zero-sum game.
///
/// Always returns `Optimal` for valid finite matrices — by von Neumann's
/// minimax theorem, every such game has an equilibrium in mixed strategies.
pub fn solve_zero_sum(matrix : FiniteMatrix) -> LpResult raise SolverError {
  let rows = matrix.rows()
  let cols = matrix.cols()
  let min_e = min_entry(matrix)
  // Shift so that all entries of A' are ≥ 1 (strictly positive value guaranteed).
  let shift = if min_e < 1.0 { 1.0 - min_e } else { 0.0 }
  let shifted = Array::make(rows, ([] : Array[Double]))
  for r in 0..<rows {
    let row = Array::make(cols, 0.0)
    for c in 0..<cols {
      row[c] = matrix.at(r, c) + shift
    }
    shifted[r] = row
  }
  let y = solve_row_lp(shifted, rows, cols)
  let x = solve_col_lp(shifted, rows, cols)
  let mut sum_y = 0.0
  for i in 0..<rows {
    sum_y += y[i]
  }
  if sum_y <= 0.0 {
    raise InconsistentGame("zero row LP sum")
  }
  let mut sum_x = 0.0
  for j in 0..<cols {
    sum_x += x[j]
  }
  if sum_x <= 0.0 {
    raise InconsistentGame("zero col LP sum")
  }
  let v_shifted = 1.0 / sum_y
  let value = v_shifted - shift
  let p = Array::make(rows, 0.0)
  for i in 0..<rows {
    p[i] = y[i] / sum_y
  }
  let q = Array::make(cols, 0.0)
  for j in 0..<cols {
    q[j] = x[j] / sum_x
  }
  let row_strategy = match MixedStrategy::new(p) {
    Ok(s) => s
    Err(_) => MixedStrategy::uniform(rows)
  }
  let col_strategy = match MixedStrategy::new(q) {
    Ok(s) => s
    Err(_) => MixedStrategy::uniform(cols)
  }
  Optimal(value~, row_strategy~, col_strategy~)
}

///|
/// Exploitability of a pair of mixed strategies against the payoff matrix.
///
/// Defined as `max_j (Aᵀp)[j] − min_i (Aq)[i]`, which is 0 iff (p, q) is a
/// Nash equilibrium (up to floating-point tolerance).
pub fn exploitability(
  matrix : FiniteMatrix,
  row : MixedStrategy,
  col : MixedStrategy,
) -> Double {
  let rows = matrix.rows()
  let cols = matrix.cols()
  // Best response of col player to p: minimize (Aᵀp)[j] = Σ_i A[i,j] p_i over j.
  // Value to row player if col plays best response = min_j Σ_i A[i,j] p_i.
  let mut best_col_value = 0.0
  let mut init_col = false
  for j in 0..<cols {
    let mut s = 0.0
    for i in 0..<rows {
      s += matrix.at(i, j) * row.at(i)
    }
    if not(init_col) || s < best_col_value {
      best_col_value = s
      init_col = true
    }
  }
  // Best response of row player to q: maximize (Aq)[i] over i.
  let mut best_row_value = 0.0
  let mut init_row = false
  for i in 0..<rows {
    let mut s = 0.0
    for j in 0..<cols {
      s += matrix.at(i, j) * col.at(j)
    }
    if not(init_row) || s > best_row_value {
      best_row_value = s
      init_row = true
    }
  }
  best_row_value - best_col_value
}
