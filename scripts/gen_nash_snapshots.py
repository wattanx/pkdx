#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "nashpy>=0.0.41",
#   "numpy>=1.26",
# ]
# ///
"""Generate Nash equilibrium golden data from nashpy.

Produces `pkdx/src/nash/__snapshots__/nashpy_cases.json` containing value +
mixed strategies for well-known matrices (RPS, matching pennies, Shapley's
degenerate 3x3, and a few randomised 4x4 / 5x5 cases).

Usage:
    uv run scripts/gen_nash_snapshots.py > pkdx/src/nash/__snapshots__/nashpy_cases.json

The resulting JSON is consumed by MoonBit tests that want an independent
baseline from nashpy (MIT, https://github.com/drvinceknight/Nashpy).

Snapshot schema:
    {
      "cases": [
        {
          "name": "rps",
          "matrix": [[0, 1, -1], [-1, 0, 1], [1, -1, 0]],
          "value": 0.0,
          "row_strategy": [0.333, 0.333, 0.333],
          "col_strategy": [0.333, 0.333, 0.333]
        },
        ...
      ],
      "meta": {
        "nashpy_version": "0.0.41",
        "numpy_version": "1.26.0",
        "seed": 42
      }
    }
"""
import json
import sys
from typing import Any

import nashpy as nash
import numpy as np


def first_equilibrium(matrix: np.ndarray) -> tuple[float, list[float], list[float]]:
    """Return (value, row_strategy, col_strategy) for the zero-sum game.

    Uses nashpy's vertex enumeration and selects the first equilibrium.
    For multi-equilibrium cases (e.g. Shapley), this yields one valid Nash;
    downstream tests should only assert value + exploitability, not the
    specific strategy vector.
    """
    game = nash.Game(matrix, -matrix)
    equilibria = list(game.vertex_enumeration())
    if not equilibria:
        # Fall back to support enumeration.
        equilibria = list(game.support_enumeration())
    if not equilibria:
        raise RuntimeError("no equilibrium found")
    p, q = equilibria[0]
    value = float(p @ matrix @ q)
    return value, [float(x) for x in p], [float(x) for x in q]


def build_cases() -> list[dict[str, Any]]:
    """Build the canonical case list. Order is stable so diffs are readable."""
    rng = np.random.default_rng(42)
    cases: list[dict[str, Any]] = []

    # Rock-Paper-Scissors (uniform 1/3 equilibrium).
    rps = np.array([[0, 1, -1], [-1, 0, 1], [1, -1, 0]], dtype=float)
    v, p, q = first_equilibrium(rps)
    cases.append({
        "name": "rps",
        "matrix": rps.tolist(),
        "value": v,
        "row_strategy": p,
        "col_strategy": q,
    })

    # Matching pennies.
    mp = np.array([[1, -1], [-1, 1]], dtype=float)
    v, p, q = first_equilibrium(mp)
    cases.append({
        "name": "matching_pennies",
        "matrix": mp.tolist(),
        "value": v,
        "row_strategy": p,
        "col_strategy": q,
    })

    # Saddle-point game: pure equilibrium at (1, 1).
    saddle = np.array([[3, 2, 5], [4, 1, 6], [2, 0, 3]], dtype=float)
    v, p, q = first_equilibrium(saddle)
    cases.append({
        "name": "saddle_point",
        "matrix": saddle.tolist(),
        "value": v,
        "row_strategy": p,
        "col_strategy": q,
    })

    # Shapley's degenerate 3x3 (value 0, uniform equilibrium despite cycle).
    shapley = np.array(
        [
            [1, -1, 0],
            [0, 1, -1],
            [-1, 0, 1],
        ],
        dtype=float,
    )
    v, p, q = first_equilibrium(shapley)
    cases.append({
        "name": "shapley_3x3",
        "matrix": shapley.tolist(),
        "value": v,
        "row_strategy": p,
        "col_strategy": q,
    })

    # Monocycle / janken baseline from the pokemon-matrixgame-pyran19 repo.
    janken = np.array(
        [
            [0.0, 3.4, -3.4],
            [-3.4, 0.0, 3.4],
            [3.4, -3.4, 0.0],
        ],
        dtype=float,
    )
    v, p, q = first_equilibrium(janken)
    cases.append({
        "name": "monocycle_janken",
        "matrix": janken.tolist(),
        "value": v,
        "row_strategy": p,
        "col_strategy": q,
    })

    # Randomised 4x4 and 5x5 cases with bounded entries to avoid unbounded LPs.
    for size in (4, 5):
        raw = rng.uniform(-2.0, 2.0, size=(size, size))
        # Force zero-sum: symmetrise by antisymmetric part only.
        raw = (raw - raw.T) / 2.0
        v, p, q = first_equilibrium(raw)
        cases.append({
            "name": f"random_{size}x{size}",
            "matrix": raw.tolist(),
            "value": v,
            "row_strategy": p,
            "col_strategy": q,
        })

    return cases


def main() -> None:
    cases = build_cases()
    payload = {
        "cases": cases,
        "meta": {
            "nashpy_version": nash.__version__,
            "numpy_version": np.__version__,
            "seed": 42,
        },
    }
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
