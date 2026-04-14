///|
/// Generate a 6-Pokemon test team with varied stats. Each member has a single
/// neutral move so that character-level payoffs are driven mostly by stats and
/// type matchup.
fn mk_team_six() -> Array[Combatant] {
  let mv = mk_move("のしかかり", "ノーマル", @model.Physical, 85)
  [
    mk_combatant(
      mk_pokemon("P0", "ノーマル", "", 100, 110, 80, 80, 80, 100),
      [mv],
    ),
    mk_combatant(
      mk_pokemon("P1", "ノーマル", "", 100, 100, 80, 80, 80, 110),
      [mv],
    ),
    mk_combatant(
      mk_pokemon("P2", "ノーマル", "", 100, 120, 80, 80, 80, 90),
      [mv],
    ),
    mk_combatant(
      mk_pokemon("P3", "ノーマル", "", 100, 90, 80, 80, 80, 120),
      [mv],
    ),
    mk_combatant(
      mk_pokemon("P4", "ノーマル", "", 100, 100, 80, 80, 80, 105),
      [mv],
    ),
    mk_combatant(
      mk_pokemon("P5", "ノーマル", "", 100, 105, 80, 80, 80, 95),
      [mv],
    ),
  ]
}

///|
test "team_game_value_derived_from_character_nash" {
  // Pick a 4-Pokemon team (single format, 3-pick → C(4,3) = 4 selections).
  // Verify cell (0, 0) of the team matrix equals the Nash value of the
  // sub-matrix over the first selection on both sides.
  let team = mk_team_six()
  let four_a = [team[0], team[1], team[2], team[3]]
  let four_b = [team[0], team[1], team[2], team[3]]
  let team_m = team_payoff_matrix(four_a, four_b, Single, Best1v1)
  // Selections in lex order: [0,1,2] is index 0.
  let ind = cross_payoff(four_a, four_b, Best1v1)
  let data = [
    [ind.at(0, 0), ind.at(0, 1), ind.at(0, 2)],
    [ind.at(1, 0), ind.at(1, 1), ind.at(1, 2)],
    [ind.at(2, 0), ind.at(2, 1), ind.at(2, 2)],
  ]
  let sub = @nash.FiniteMatrix::new(data).unwrap()
  let expected = match @nash.solve_zero_sum(sub) {
    Optimal(value~, ..) => value
    _ => {
      assert_true(false)
      0.0
    }
  }
  assert_true((team_m.at(0, 0) - expected).abs() < 1.0e-9)
}

///|
test "team_ordering_canonical_permutation_is_stable" {
  // combinations() must enumerate in stable lex order regardless of call site.
  let a = combinations(4, 3)
  let b = combinations(4, 3)
  inspect(a.length(), content="4")
  inspect(b.length(), content="4")
  // Lex order of C(4, 3): [0,1,2], [0,1,3], [0,2,3], [1,2,3]
  for i in 0..<a.length() {
    for j in 0..<3 {
      assert_true(a[i][j] == b[i][j])
    }
  }
  inspect(a[0], content="[0, 1, 2]")
  inspect(a[1], content="[0, 1, 3]")
  inspect(a[2], content="[0, 2, 3]")
  inspect(a[3], content="[1, 2, 3]")
}

///|
test "single_3v3_payoff_matrix_shape_20x20" {
  let team_a = mk_team_six()
  let team_b = mk_team_six()
  let m = team_payoff_matrix(team_a, team_b, Single, Best1v1)
  inspect(m.rows(), content="20")
  inspect(m.cols(), content="20")
}

///|
test "double_4v4_payoff_matrix_shape_15x15" {
  let team_a = mk_team_six()
  let team_b = mk_team_six()
  let m = team_payoff_matrix(team_a, team_b, Double, Best1v1)
  inspect(m.rows(), content="15")
  inspect(m.cols(), content="15")
}
