///|
test "exploitability_zero_at_true_nash_and_positive_otherwise" {
  // RPS: uniform is Nash, so NashConv = 0.
  let a = FiniteMatrix::new([
    [0.0, -1.0, 1.0],
    [1.0, 0.0, -1.0],
    [-1.0, 1.0, 0.0],
  ]).unwrap()
  let uniform = MixedStrategy::uniform(3)
  assert_true(nashconv(a, uniform, uniform).abs() < 1.0e-12)

  // Pure (1,0,0) vs uniform: row can exploit since (0,-1,1) · (1/3,1/3,1/3) = 0
  // but a better row strategy exists. Specifically row 1 gets 0 against uniform,
  // row 0 (rock) gets 0 too — RPS is balanced against uniform, so row_expl = 0.
  // Use a skewed matrix instead:
  let b = FiniteMatrix::new([[1.0, 0.0], [0.0, 2.0]]).unwrap()
  let off = MixedStrategy::new([1.0, 0.0]).unwrap()
  let anti = MixedStrategy::new([0.0, 1.0]).unwrap()
  // (1,0) vs (0,1) yields 0; col can move to (1,0) losing only 0 (still 0).
  // But row can switch to (0,1) and get 2. So row_expl > 0.
  assert_true(row_exploitability(b, off, anti) > 0.5)
  assert_true(nashconv(b, off, anti) > 0.5)
}

///|
test "nashconv_equals_sum_of_both_player_exploitabilities" {
  // For any (p, q), nashconv = row_expl + col_expl by definition.
  let a = FiniteMatrix::new([[3.0, 1.0, 4.0], [1.0, 5.0, 9.0], [2.0, 6.0, 5.0]]).unwrap()
  let p = MixedStrategy::new([0.2, 0.3, 0.5]).unwrap()
  let q = MixedStrategy::new([0.1, 0.6, 0.3]).unwrap()
  let re = row_exploitability(a, p, q)
  let ce = col_exploitability(a, p, q)
  let nc = nashconv(a, p, q)
  assert_true((nc - (re + ce)).abs() < 1.0e-12)
  // For zero-sum, nashconv also equals max_i(Aq)[i] − min_j(pᵀA)[j].
  assert_true(re >= 0.0)
  assert_true(ce >= 0.0)
}

///|
test "kl_divergence_properties" {
  // 1. Non-negativity (Gibbs): D_KL(P ‖ Q) ≥ 0 for any P, Q.
  let p = MixedStrategy::new([0.4, 0.6]).unwrap()
  let q = MixedStrategy::new([0.5, 0.5]).unwrap()
  assert_true(kl_divergence(p, q) >= 0.0)
  assert_true(kl_divergence(q, p) >= 0.0)
  // 2. Zero iff P == Q.
  assert_true(kl_divergence(p, p).abs() < 1.0e-12)
  assert_true(kl_divergence(q, q).abs() < 1.0e-12)
  // 3. Infinity when Q has zero where P doesn't.
  let p_pos = MixedStrategy::new([0.5, 0.5]).unwrap()
  let q_zero = MixedStrategy::new([1.0, 0.0]).unwrap()
  assert_true(kl_divergence(p_pos, q_zero).is_inf())
  // 4. Zero with zero entries on P side (limit 0 log 0 = 0).
  let p_has_zero = MixedStrategy::new([0.0, 1.0]).unwrap()
  let q_full = MixedStrategy::new([0.5, 0.5]).unwrap()
  let d = kl_divergence(p_has_zero, q_full)
  // 1 * ln(1 / 0.5) = ln 2 ≈ 0.693
  assert_true((d - @math.ln(2.0)).abs() < 1.0e-9)
}

///|
test "l1_divergence_triangle_inequality" {
  // L1 distance satisfies ‖P − R‖₁ ≤ ‖P − Q‖₁ + ‖Q − R‖₁.
  let p = MixedStrategy::new([0.1, 0.4, 0.5]).unwrap()
  let q = MixedStrategy::new([0.5, 0.3, 0.2]).unwrap()
  let r = MixedStrategy::new([0.3, 0.3, 0.4]).unwrap()
  let pq = l1_distance(p, q)
  let qr = l1_distance(q, r)
  let pr = l1_distance(p, r)
  assert_true(pr <= pq + qr + 1.0e-12)
  // Symmetry: ‖P − Q‖ = ‖Q − P‖
  assert_true((l1_distance(p, q) - l1_distance(q, p)).abs() < 1.0e-12)
  // Identity: ‖P − P‖ = 0
  assert_true(l1_distance(p, p).abs() < 1.0e-12)
}
