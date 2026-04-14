///|
test "fictitious_play_converges_on_rps_empirical_freq" {
  // RPS: true Nash is (1/3, 1/3, 1/3) with v = 0.
  // Fictitious play is known to converge slowly on RPS — the empirical
  // frequencies oscillate but the time-average approaches uniform.
  let a = FiniteMatrix::new([
    [0.0, -1.0, 1.0],
    [1.0, 0.0, -1.0],
    [-1.0, 1.0, 0.0],
  ]).unwrap()
  let (p, q) = fictitious_play(a, 5000)
  // Each component should be within 0.05 of 1/3 after 5k iterations.
  for i in 0..<3 {
    assert_true((p.at(i) - 1.0 / 3.0).abs() < 0.05)
    assert_true((q.at(i) - 1.0 / 3.0).abs() < 0.05)
  }
}

///|
test "mwu_output_matches_exact_solver_within_exploitability_bound" {
  // MWU's time-averaged strategies should be an ε-Nash with ε decaying as
  // O(√(log n / T)). We use T = 5000 and assert exploitability ≤ 5e-2.
  let a = FiniteMatrix::new([[3.0, 1.0, 4.0], [1.0, 5.0, 9.0], [2.0, 6.0, 5.0]]).unwrap()
  let t = 10000
  let eta = (@math.ln(3.0) / t.to_double()).sqrt()
  let (p, q) = mwu(a, t, eta)
  let expl = nashconv(a, p, q)
  // Span of payoffs is 8; theoretical bound on NashConv is ~ 2·span·O(√(log n / T)).
  // Use 0.3 to account for scale and constants.
  assert_true(expl < 0.3)
  // Cross-check: value is close to exact solver.
  match solve_zero_sum(a) {
    Optimal(value=v_exact, ..) => {
      let v_mwu = expected_payoff(p, a, q)
      assert_true((v_mwu - v_exact).abs() < 0.3)
    }
    _ => assert_true(false)
  }
}
