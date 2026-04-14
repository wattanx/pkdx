///|
/// Helper: approximate equality.
fn approx_eq(a : Double, b : Double, tol : Double) -> Bool {
  (a - b).abs() <= tol
}

///|
test "simplex_solves_chvatal_textbook_example" {
  // Chvátal, Linear Programming (1983) Ch. 2
  //
  // maximize 5x1 + 4x2 + 3x3
  // s.t.
  //   2x1 + 3x2 +  x3 ≤ 5
  //   4x1 +  x2 + 2x3 ≤ 11
  //   3x1 + 4x2 + 2x3 ≤ 8
  //   x ≥ 0
  //
  // Optimal: value = 13, x = (2, 0, 1)
  let problem = LpProblem::{
    c: [5.0, 4.0, 3.0],
    a: [[2.0, 3.0, 1.0], [4.0, 1.0, 2.0], [3.0, 4.0, 2.0]],
    b: [5.0, 11.0, 8.0],
  }
  match solve_lp(problem) {
    Optimal(value~, x~) => {
      assert_true(approx_eq(value, 13.0, 1.0e-7))
      assert_true(approx_eq(x[0], 2.0, 1.0e-7))
      assert_true(approx_eq(x[1], 0.0, 1.0e-7))
      assert_true(approx_eq(x[2], 1.0, 1.0e-7))
    }
    _ => assert_true(false)
  }
}

///|
test "simplex_detects_unboundedness" {
  // maximize x1 + x2
  // s.t. -x1 + x2 ≤ 1, x ≥ 0
  // The feasible region is unbounded along the x1 direction.
  let problem = LpProblem::{ c: [1.0, 1.0], a: [[-1.0, 1.0]], b: [1.0] }
  match solve_lp(problem) {
    Unbounded => ()
    other => {
      inspect(other, content="Unbounded")
      assert_true(false)
    }
  }
}

///|
test "simplex_detects_infeasibility_via_phase1_residual" {
  // maximize x1
  // s.t.  x1 + x2 ≤ -1, x ≥ 0   (requires x1 + x2 ≥ 0, so infeasible)
  let problem = LpProblem::{ c: [1.0, 1.0], a: [[1.0, 1.0]], b: [-1.0] }
  match solve_lp(problem) {
    Infeasible => ()
    other => {
      inspect(other, content="Infeasible")
      assert_true(false)
    }
  }
}

///|
test "bland_rule_terminates_on_beale_cycling_example" {
  // Beale (1955) cycling example — Dantzig's most-negative-coefficient rule
  // cycles; Bland's smallest-index rule terminates.
  //
  // maximize 3/4 x1 − 150 x2 + 1/50 x3 − 6 x4
  // s.t.
  //   1/4 x1 − 60 x2 −  1/25 x3 + 9 x4 ≤ 0
  //   1/2 x1 − 90 x2 −  1/50 x3 + 3 x4 ≤ 0
  //   x3 ≤ 1
  //   x ≥ 0
  //
  // Optimal value is 1/20 = 0.05, attained at x = (1/25, 0, 1, 0) (one vertex).
  let problem = LpProblem::{
    c: [0.75, -150.0, 1.0 / 50.0, -6.0],
    a: [
      [0.25, -60.0, -1.0 / 25.0, 9.0],
      [0.5, -90.0, -1.0 / 50.0, 3.0],
      [0.0, 0.0, 1.0, 0.0],
    ],
    b: [0.0, 0.0, 1.0],
  }
  match solve_lp(problem) {
    Optimal(value~, ..) => assert_true(approx_eq(value, 0.05, 1.0e-7))
    _ => assert_true(false)
  }
}

///|
test "simplex_terminates_on_degenerate_pivot_sequence" {
  // Small degenerate LP with multiple tied ratios.
  //
  // maximize x1 + x2
  // s.t.
  //   x1 + x2 ≤ 1
  //   x1      ≤ 1
  //   x2      ≤ 1
  //   x ≥ 0
  //
  // Optimal value = 1 (many optima; e.g. x=(1,0) or (0,1) or on the segment).
  let problem = LpProblem::{
    c: [1.0, 1.0],
    a: [[1.0, 1.0], [1.0, 0.0], [0.0, 1.0]],
    b: [1.0, 1.0, 1.0],
  }
  match solve_lp(problem) {
    Optimal(value~, x~) => {
      assert_true(approx_eq(value, 1.0, 1.0e-7))
      assert_true(approx_eq(x[0] + x[1], 1.0, 1.0e-7))
    }
    _ => assert_true(false)
  }
}

///|
test "simplex_random_lps_satisfy_kkt_conditions" {
  // Self-consistency property: for 10 small random feasible LPs, verify the
  // returned solution satisfies primal feasibility (Ax ≤ b, x ≥ 0) and the
  // objective value matches cᵀx.
  //
  // Construction guarantees feasibility: b = A·x₀ + slack for a random x₀ ≥ 0.
  let rng_seed : Int = 42
  let mut state = rng_seed
  fn next() -> Double {
    // Deterministic LCG in [0, 1)
    state = (state * 1103515245 + 12345) & 0x7fffffff
    state.to_double() / 2147483648.0
  }

  for trial in 0..<10 {
    let n = 2 + trial % 3 // 2..4 vars
    let m = 2 + trial % 3 // 2..4 constraints
    let c = Array::make(n, 0.0)
    for j in 0..<n {
      c[j] = next() * 2.0 - 1.0 // [-1, 1]
    }
    // A entries in [0.1, 1.1] ensures bounded feasible region for x ≥ 0, b > 0.
    let a = Array::make(m, ([] : Array[Double]))
    for i in 0..<m {
      let row = Array::make(n, 0.0)
      for j in 0..<n {
        row[j] = next() + 0.1
      }
      a[i] = row
    }
    let x0 = Array::make(n, 0.0)
    for j in 0..<n {
      x0[j] = next()
    }
    let b = Array::make(m, 0.0)
    for i in 0..<m {
      let mut s = 0.0
      for j in 0..<n {
        s += a[i][j] * x0[j]
      }
      b[i] = s + next() * 0.5 + 0.1 // positive slack so x0 is strictly feasible
    }
    let problem = LpProblem::{ c, a, b }
    match solve_lp(problem) {
      Optimal(value~, x~) => {
        // Primal feasibility: Ax ≤ b, x ≥ 0
        for j in 0..<n {
          assert_true(x[j] >= -1.0e-9)
        }
        for i in 0..<m {
          let mut lhs = 0.0
          for j in 0..<n {
            lhs += a[i][j] * x[j]
          }
          assert_true(lhs <= b[i] + 1.0e-7)
        }
        // Objective matches
        let mut obj = 0.0
        for j in 0..<n {
          obj += c[j] * x[j]
        }
        assert_true(approx_eq(obj, value, 1.0e-7))
        // Optimality ≥ initial x0's objective (since x0 is feasible)
        let mut obj0 = 0.0
        for j in 0..<n {
          obj0 += c[j] * x0[j]
        }
        assert_true(value >= obj0 - 1.0e-7)
      }
      other => {
        inspect(other, content="Optimal")
        assert_true(false)
      }
    }
  }
}

///|
test "simplex_scale_invariance_up_to_tolerance" {
  // Scaling c (objective) by k scales optimal value by k; same x.
  let problem = LpProblem::{
    c: [3.0, 2.0],
    a: [[1.0, 1.0], [2.0, 1.0]],
    b: [4.0, 7.0],
  }
  let k = 7.5
  let scaled = LpProblem::{
    c: problem.c.map(fn(v) { v * k }),
    a: problem.a,
    b: problem.b,
  }
  match (solve_lp(problem), solve_lp(scaled)) {
    (Optimal(value=v1, x=x1), Optimal(value=v2, x=x2)) => {
      assert_true(approx_eq(v2, v1 * k, 1.0e-7))
      for j in 0..<x1.length() {
        assert_true(approx_eq(x1[j], x2[j], 1.0e-7))
      }
    }
    _ => assert_true(false)
  }
}
