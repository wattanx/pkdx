///|
/// Helper: janken (rock-paper-scissors) payoff matrix as a JSON string.
fn janken_json() -> String {
  "{\"matrix\":[[0,1,-1],[-1,0,1],[1,-1,0]],\"labels\":[\"R\",\"P\",\"S\"]}"
}

///|
test "nash_solve_json_matrix_form" {
  let out = run_nash_solve(janken_json())
  // Must contain the required top-level fields.
  assert_true(out.contains("\"value\":"))
  assert_true(out.contains("\"row_strategy\":"))
  assert_true(out.contains("\"col_strategy\":"))
  assert_true(out.contains("\"exploitability\":"))
  assert_true(out.contains("\"support\":"))
  assert_true(out.contains("\"labels\":"))
}

///|
test "nash_solve_rejects_both_matrix_and_characters" {
  let bad =
    #|{"matrix": [[0, 1], [-1, 0]], "characters": [{"label": "A", "power": 0, "v": {"x": 1, "y": 0}}]}
  let err = try? run_nash_solve(bad)
  assert_true(err is Err(ConflictingInputs))
}

///|
test "nash_solve_rejects_non_square" {
  let bad = "{\"matrix\":[[0,1,-1],[1,0]]}"
  let err = try? run_nash_solve(bad)
  assert_true(err is Err(NonSquareMatrix(_, _)))
}

///|
test "nash_solve_output_json_schema_validates" {
  // Parse the output and verify each required field has the expected type.
  let out = run_nash_solve(janken_json())
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("value") {
        Some(Number(_, ..)) => ()
        _ => {
          assert_true(false)
          return
        }
      }
      match m.get("row_strategy") {
        Some(Array(arr)) => assert_true(arr.length() == 3)
        _ => {
          assert_true(false)
          return
        }
      }
      match m.get("col_strategy") {
        Some(Array(arr)) => assert_true(arr.length() == 3)
        _ => {
          assert_true(false)
          return
        }
      }
      match m.get("exploitability") {
        Some(Number(_, ..)) => ()
        _ => assert_true(false)
      }
      match m.get("support") {
        Some(Object(s)) => {
          assert_true(s.contains("row"))
          assert_true(s.contains("col"))
        }
        _ => assert_true(false)
      }
      match m.get("labels") {
        Some(Array(arr)) => assert_true(arr.length() == 3)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "nash_solve_reproduces_monocycle_nash_janken_e2e" {
  // RPS: value = 0, uniform 1/3 strategy. Check via parsed output.
  let out = run_nash_solve(janken_json())
  let j = @json.parse(out)
  match j {
    Object(m) => {
      match m.get("value") {
        Some(Number(v, ..)) => assert_true(v.abs() < 1.0e-7)
        _ => assert_true(false)
      }
      match m.get("row_strategy") {
        Some(Array(arr)) =>
          for i in 0..<3 {
            match arr[i] {
              Number(p, ..) => assert_true((p - 1.0 / 3.0).abs() < 1.0e-6)
              _ => assert_true(false)
            }
          }
        _ => assert_true(false)
      }
      match m.get("exploitability") {
        Some(Number(e, ..)) => assert_true(e < 1.0e-6)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "nash_solve_nonzero_exit_on_infeasible" {
  // Invalid JSON triggers InvalidJson error → CLI would exit non-zero.
  let err = try? run_nash_solve("not json at all")
  assert_true(err is Err(InvalidJson(_)))
}

///|
///|
/// Count non-overlapping " -> " occurrences in `s`.
fn count_arrows(s : String) -> Int {
  let mut count = 0
  let mut i = 0
  while i + 3 < s.length() {
    if s[i] == ' ' && s[i + 1] == '-' && s[i + 2] == '>' && s[i + 3] == ' ' {
      count = count + 1
      i = i + 4
    } else {
      i = i + 1
    }
  }
  count
}

///|
test "nash_graph_outputs_dot_with_threshold_filter" {
  let out = run_nash_graph(janken_json(), 0.5)
  assert_true(out.contains("digraph payoff"))
  // All RPS off-diagonal entries are ±1, which exceed 0.5 → 6 edges.
  inspect(count_arrows(out), content="6")
  // With a threshold above max entry magnitude, no edges remain.
  let sparse = run_nash_graph(janken_json(), 2.0)
  inspect(count_arrows(sparse), content="0")
}

///|
test "nash_graph_node_labels_match_input" {
  let out = run_nash_graph(janken_json(), 0.5)
  assert_true(out.contains("\"R\""))
  assert_true(out.contains("\"P\""))
  assert_true(out.contains("\"S\""))
  // Without labels, nodes fall back to numeric indices.
  let numbered = run_nash_graph(
    "{\"matrix\":[[0,1,-1],[-1,0,1],[1,-1,0]]}", 0.5,
  )
  assert_true(numbered.contains("\"0\""))
  assert_true(numbered.contains("\"2\""))
}
