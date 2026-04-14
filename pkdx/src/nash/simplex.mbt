///|
/// Tableau simplex method for linear programming.
///
/// Solves standard form LPs:
///
/// ```
/// maximize cᵀx
/// subject to Ax ≤ b
///            x ≥ 0
/// ```
///
/// `b` may contain negative entries; Phase 1 with artificial variables finds an
/// initial basic feasible solution.
///
/// References:
/// - Chvátal, *Linear Programming* (1983), Ch. 2, 3
/// - Bertsimas & Tsitsiklis, *Introduction to Linear Optimization* §3.3–3.5
/// - Bland (1977) "New finite pivoting rules", DOI:10.1287/moor.2.2.103

///|
pub(all) struct LpProblem {
  c : Array[Double]
  a : Array[Array[Double]]
  b : Array[Double]
} derive(Show, Eq)

///|
pub(all) enum SimplexStatus {
  Optimal(value~ : Double, x~ : Array[Double])
  Infeasible
  Unbounded
} derive(Show, Eq)

///|
/// Maximum pivot iterations before bailing out. Bland's rule guarantees
/// termination, but this caps pathological inputs.
const MAX_ITERS : Int = 5000

///|
/// Pivot comparison tolerance — values with magnitude below are treated as zero.
const PIVOT_EPS : Double = 1.0e-12

///|
/// Optimal/feasibility tolerance for reduced costs and Phase 1 residual.
const OPT_EPS : Double = 1.0e-9

///|
/// Internal tableau representation. Row `m` is the objective row.
///
/// Columns layout (width = n + m + 1):
///
/// - `0..n`         : original variables `x`
/// - `n..n+m`       : slacks (Phase 2) or slacks+artificials interleaved (Phase 1)
/// - `n+m`          : RHS / current objective value (for row `m`)
priv struct Tableau {
  t : Array[Array[Double]]
  m : Int // number of constraints (rows 0..m-1)
  n_total : Int // total columns minus 1 (width of variable block)
  basis : Array[Int] // length m; basis[i] = column index of the basic variable in row i
}

///|
fn Tableau::rhs(self : Tableau, row : Int) -> Double {
  self.t[row][self.n_total]
}

///|
fn Tableau::entry(self : Tableau, row : Int, col : Int) -> Double {
  self.t[row][col]
}

///|
/// Pivot on (pivot_row, pivot_col): normalize pivot row, eliminate column in others.
fn Tableau::pivot(self : Tableau, pivot_row : Int, pivot_col : Int) -> Unit {
  let width = self.n_total + 1
  let pivot = self.t[pivot_row][pivot_col]
  for c in 0..<width {
    self.t[pivot_row][c] = self.t[pivot_row][c] / pivot
  }
  for r in 0..<(self.m + 1) {
    if r == pivot_row {
      continue
    }
    let factor = self.t[r][pivot_col]
    if factor.abs() < PIVOT_EPS {
      continue
    }
    for c in 0..<width {
      self.t[r][c] = self.t[r][c] - factor * self.t[pivot_row][c]
    }
  }
  self.basis[pivot_row] = pivot_col
}

///|
/// Bland's rule: smallest-index column with strictly negative objective-row entry.
/// Returns -1 if no entering column exists (i.e. at optimum for current objective).
fn Tableau::choose_entering(self : Tableau) -> Int {
  let obj_row = self.m
  for c in 0..<self.n_total {
    if self.t[obj_row][c] < -OPT_EPS {
      return c
    }
  }
  -1
}

///|
/// Bland's rule: among rows with positive pivot-column entry, pick the one with
/// the smallest ratio rhs / entry; break ties by smallest basis-variable index.
/// Returns -1 if no such row (unbounded).
fn Tableau::choose_leaving(self : Tableau, entering : Int) -> Int {
  let mut leaving = -1
  let mut best_ratio = 0.0
  for r in 0..<self.m {
    let a = self.t[r][entering]
    if a > PIVOT_EPS {
      let ratio = self.t[r][self.n_total] / a
      if leaving == -1 ||
        ratio < best_ratio - OPT_EPS ||
        (ratio < best_ratio + OPT_EPS && self.basis[r] < self.basis[leaving]) {
        leaving = r
        best_ratio = ratio
      }
    }
  }
  leaving
}

///|
/// Run pivot iterations until optimality, unboundedness, or MAX_ITERS.
/// Returns `true` if optimal, `false` if unbounded.
fn Tableau::optimize(self : Tableau) -> Bool raise SimplexError {
  for _iter in 0..<MAX_ITERS {
    let entering = self.choose_entering()
    if entering == -1 {
      return true
    }
    let leaving = self.choose_leaving(entering)
    if leaving == -1 {
      return false
    }
    self.pivot(leaving, entering)
  }
  raise IterationLimit
}

///|
pub suberror SimplexError {
  IterationLimit
  InvalidInput(String)
} derive(Show)

///|
/// Solve a standard-form LP by two-phase tableau simplex with Bland's rule.
pub fn solve_lp(problem : LpProblem) -> SimplexStatus raise SimplexError {
  let m = problem.a.length()
  if m == 0 {
    raise InvalidInput("no constraints")
  }
  let n = problem.c.length()
  if n == 0 {
    raise InvalidInput("empty objective")
  }
  if problem.b.length() != m {
    raise InvalidInput("b dimension mismatch")
  }
  for r in 0..<m {
    if problem.a[r].length() != n {
      raise InvalidInput("A row dimension mismatch")
    }
  }

  // Flip rows with negative b so RHS is non-negative; this makes the slack an
  // immediately usable basic variable for that row in Phase 1.
  let a = Array::make(m, ([] : Array[Double]))
  let b = Array::make(m, 0.0)
  let flipped = Array::make(m, false)
  for r in 0..<m {
    let row = Array::make(n, 0.0)
    if problem.b[r] < 0.0 {
      for c in 0..<n {
        row[c] = -problem.a[r][c]
      }
      b[r] = -problem.b[r]
      flipped[r] = true
    } else {
      for c in 0..<n {
        row[c] = problem.a[r][c]
      }
      b[r] = problem.b[r]
    }
    a[r] = row
  }

  // Phase 1: tableau of width (n + m + m + 1) = vars + slacks + artificials + RHS.
  // Slack for row r has coefficient +1 if !flipped[r], else -1 (after row flip).
  // Artificial a_r always has +1, placed at column n + m + r.
  // Objective: minimize sum of artificials → equivalently maximize −Σ a_r.
  let width1 = n + m + m + 1
  let t1 = Array::make(m + 1, ([] : Array[Double]))
  let basis1 = Array::make(m, 0)
  for r in 0..<m {
    let row = Array::make(width1, 0.0)
    for c in 0..<n {
      row[c] = a[r][c]
    }
    // Slack: +1 if original b ≥ 0, else −1 (because we flipped the row)
    row[n + r] = if flipped[r] { -1.0 } else { 1.0 }
    row[n + m + r] = 1.0 // artificial
    row[width1 - 1] = b[r]
    t1[r] = row
    basis1[r] = n + m + r // start with artificial as basis
  }
  let obj1 = Array::make(width1, 0.0)
  // maximize −Σ a_r → reduced cost for each a_r is +1 in storage (we use
  // the same "negative reduced cost triggers pivot" convention)
  for r in 0..<m {
    obj1[n + m + r] = 1.0
  }
  // Make artificials basic by subtracting their rows from the objective row.
  // Current obj row has +1 in each artificial column; rows r have +1 in (n+m+r).
  // After elimination: obj[c] -= sum_r(row_r[c]) for c in 0..width1.
  for c in 0..<width1 {
    let mut s = 0.0
    for r in 0..<m {
      s += t1[r][c]
    }
    obj1[c] = obj1[c] - s
  }
  t1[m] = obj1
  let tab1 = Tableau::{ t: t1, m, n_total: width1 - 1, basis: basis1 }
  let phase1_optimal = tab1.optimize()
  ignore(phase1_optimal) // Phase 1 is always bounded (feasible directions add a to objective, which is non-positive after sign flip)

  // Phase 1 objective value at row m = -Σ a_r. If > OPT_EPS (i.e. the
  // stored value is < -OPT_EPS), original problem is infeasible.
  let phase1_value = -tab1.rhs(m)
  if phase1_value > OPT_EPS {
    return Infeasible
  }

  // If an artificial is still basic at zero, pivot it out if possible.
  // This is important to avoid carrying artificials into Phase 2.
  for r in 0..<m {
    if tab1.basis[r] >= n + m {
      // Look for a non-artificial column with non-zero entry.
      let mut replaced = false
      for c in 0..<(n + m) {
        if tab1.entry(r, c).abs() > PIVOT_EPS {
          tab1.pivot(r, c)
          replaced = true
          break
        }
      }
      if not(replaced) {
        // Row is redundant; leave artificial in basis (its value is 0).
        // Phase 2 will treat the artificial column as implicitly excluded via a blocked pivot.
      }
    }
  }

  // Phase 2: strip artificial columns, install real objective.
  let width2 = n + m + 1
  let t2 = Array::make(m + 1, ([] : Array[Double]))
  let basis2 = Array::make(m, 0)
  for r in 0..<m {
    let row = Array::make(width2, 0.0)
    for c in 0..<(n + m) {
      row[c] = tab1.entry(r, c)
    }
    row[width2 - 1] = tab1.rhs(r)
    t2[r] = row
    basis2[r] = if tab1.basis[r] >= n + m {
      // Orphan artificial in basis at zero; keep a dummy column reference that
      // won't be chosen (we give it an out-of-range index so choose_leaving
      // ignores degeneracy on it through standard ratio test).
      // Clamp to n+r so the basis remains well-formed.
      n + r
    } else {
      tab1.basis[r]
    }
  }
  // Phase 2 objective row: maximize cᵀx → store -c in first n cols.
  let obj2 = Array::make(width2, 0.0)
  for c in 0..<n {
    obj2[c] = -problem.c[c]
  }
  // Reduce the objective row to eliminate current basic variables.
  for r in 0..<m {
    let bcol = basis2[r]
    if bcol < width2 - 1 {
      let factor = obj2[bcol]
      if factor.abs() > PIVOT_EPS {
        for c in 0..<width2 {
          obj2[c] = obj2[c] - factor * t2[r][c]
        }
      }
    }
  }
  t2[m] = obj2
  let tab2 = Tableau::{ t: t2, m, n_total: width2 - 1, basis: basis2 }
  let optimal = tab2.optimize()
  if not(optimal) {
    return Unbounded
  }

  // Extract solution: for each original variable, find its basis row if any.
  let x = Array::make(n, 0.0)
  for r in 0..<m {
    let bcol = tab2.basis[r]
    if bcol < n {
      x[bcol] = tab2.rhs(r)
    }
  }
  let value = tab2.rhs(m)
  Optimal(value~, x~)
}

///|
fn[T] ignore(_v : T) -> Unit {
  ()
}
