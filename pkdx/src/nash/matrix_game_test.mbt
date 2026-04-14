///|
test "matrix_game_new_rejects_non_rectangular" {
  let jagged : Array[Array[Double]] = [[1.0, 2.0], [3.0]]
  let result = FiniteMatrix::new(jagged)
  inspect(result, content="Err(NonRectangular)")
}

///|
test "transpose_negates_for_zero_sum" {
  // RPS payoff matrix for the row player
  let rps = FiniteMatrix::new([
    [0.0, -1.0, 1.0],
    [1.0, 0.0, -1.0],
    [-1.0, 1.0, 0.0],
  ]).unwrap()
  let opponent = rps.zero_sum_opponent()
  // Column player's payoff = -A^T => should be the same RPS structure (symmetric game)
  inspect(opponent.rows(), content="3")
  inspect(opponent.cols(), content="3")
  // -A^T[i][j] = -A[j][i]
  inspect(opponent.at(0, 1), content="-1")
  inspect(opponent.at(1, 0), content="1")
  inspect(opponent.at(2, 0), content="-1")
}

///|
test "mixed_strategy_sums_to_one_and_nonnegative" {
  // Valid uniform
  let uniform = MixedStrategy::uniform(4)
  inspect(uniform.len(), content="4")
  inspect(uniform.at(0), content="0.25")
  // Explicit valid
  let explicit = MixedStrategy::new([0.5, 0.25, 0.25])
  inspect(explicit is Ok(_), content="true")
  // Negative probability
  let neg = MixedStrategy::new([0.5, -0.1, 0.6])
  inspect(neg, content="Err(NegativeProbability)")
  // Not normalized
  let bad_sum = MixedStrategy::new([0.3, 0.3, 0.3])
  inspect(bad_sum, content="Err(NotNormalized)")
  // Empty
  let empty : Array[Double] = []
  let empty_result = MixedStrategy::new(empty)
  inspect(empty_result, content="Err(EmptyStrategy)")
}

///|
test "expected_payoff_matches_numbt_matmul" {
  // A 2x3 matrix, row player mixed over 2, col player over 3
  let a = FiniteMatrix::new([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]).unwrap()
  let p = MixedStrategy::new([0.3, 0.7]).unwrap()
  let q = MixedStrategy::new([0.2, 0.5, 0.3]).unwrap()

  // Reference via direct pᵀ A q computation
  let ours = expected_payoff(p, a, q)

  // Cross-check with numbt mat_matmul: p_row (1x2) · A (2x3) · q_col (3x1) → 1x1
  let p_row = @numbt.mat_view(
    [0.3 |> Float::from_double, 0.7 |> Float::from_double],
    1,
    2,
  )
  let a_mat = @numbt.mat_view(
    [
      1.0 |> Float::from_double,
      2.0 |> Float::from_double,
      3.0 |> Float::from_double,
      4.0 |> Float::from_double,
      5.0 |> Float::from_double,
      6.0 |> Float::from_double,
    ],
    2,
    3,
  )
  let q_col = @numbt.mat_view(
    [
      0.2 |> Float::from_double,
      0.5 |> Float::from_double,
      0.3 |> Float::from_double,
    ],
    3,
    1,
  )
  let pa = @numbt.mat_matmul(p_row, a_mat) // 1x3
  let paq = @numbt.mat_matmul(pa, q_col) // 1x1
  let numbt_ref = @numbt.mat_at(paq, 0, 0) |> Float::to_double

  // Float32 precision: allow 1e-5 tolerance
  let diff = (ours - numbt_ref).abs()
  assert_true(diff < 1.0e-5)
}

///|
test "lp_result_enum_variants_constructible" {
  let ok_variant : LpResult = Optimal(
    value=0.0,
    row_strategy=MixedStrategy::uniform(3),
    col_strategy=MixedStrategy::uniform(3),
  )
  let infeasible : LpResult = Infeasible
  let unbounded : LpResult = Unbounded
  match ok_variant {
    Optimal(value~, ..) => inspect(value, content="0")
    _ => assert_true(false)
  }
  match infeasible {
    Infeasible => assert_true(true)
    _ => assert_true(false)
  }
  match unbounded {
    Unbounded => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "finite_matrix_rejects_nan_and_inf_at_construction" {
  let nan = @double.not_a_number
  let inf = @double.infinity
  inspect(FiniteMatrix::new([[1.0, nan], [3.0, 4.0]]), content="Err(NonFinite)")
  inspect(FiniteMatrix::new([[1.0, 2.0], [3.0, inf]]), content="Err(NonFinite)")
  let empty : Array[Array[Double]] = []
  inspect(FiniteMatrix::new(empty), content="Err(Empty)")
}
