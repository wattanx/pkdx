///|
/// 4096-base rounding (五捨五超入).
pub fn round5(value : Int, mult_4096 : Int) -> Int {
  (value * mult_4096 + 2047) / 4096
}

///|
/// stage >= 0: stat * (2 + stage) / 2
/// stage <  0: stat * 2 / (2 - stage)
pub fn apply_rank(stat : Int, stage : Int) -> Int {
  let s = if stage > 6 { 6 } else if stage < -6 { -6 } else { stage }
  if s >= 0 {
    stat * (2 + s) / 2
  } else {
    stat * 2 / (2 - s)
  }
}

///|
/// Full HP stat calculation at Lv50.
/// floor((base*2 + iv + floor(ev/4)) * 50 / 100) + 60
pub fn calc_hp_full(base : Int, iv : Int, ev : Int) -> Int {
  (base * 2 + iv + ev / 4) * 50 / 100 + 60
}

///|
/// Full non-HP stat calculation at Lv50.
/// floor((floor((base*2 + iv + floor(ev/4)) * 50 / 100) + 5) * nature_num / nature_den)
pub fn calc_other_full(
  base : Int,
  iv : Int,
  ev : Int,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  let raw = (base * 2 + iv + ev / 4) * 50 / 100 + 5
  raw * nature_num / nature_den
}

///|
/// Lv50 stat calculation (IV31, EV252 shortcut).
/// Delegates to calc_hp_full / calc_other_full.
pub fn calc_stat(
  base : Int,
  is_hp? : Bool = false,
  nature_boost? : Bool = true,
  custom? : Int = 0,
) -> Int {
  if custom > 0 {
    return custom
  }
  if is_hp {
    return calc_hp_full(base, 31, 252)
  }
  let (num, den) = if nature_boost { (11, 10) } else { (1, 1) }
  calc_other_full(base, 31, 252, num, den)
}

///|
/// Calculate all 6 stats for a Pokemon at Lv50.
/// ivs/evs: FixedArray of 6 values in HP,Atk,Def,SpA,SpD,Spe order.
pub fn calc_all_stats(
  pokemon : @model.Pokemon,
  ivs : FixedArray[Int],
  evs : FixedArray[Int],
  nature : @model.Nature,
) -> FixedArray[Int] {
  let bases : FixedArray[Int] = [
    pokemon.hp, pokemon.atk, pokemon.def_, pokemon.spa, pokemon.spd,
    pokemon.spe,
  ]
  let stat_indices : FixedArray[@model.StatIndex] = [
    HP, Atk, Def, SpA, SpD, Spe,
  ]
  let result : FixedArray[Int] = FixedArray::make(6, 0)
  for i = 0; i < 6; i = i + 1 {
    if i == 0 {
      result[i] = calc_hp_full(bases[i], ivs[i], evs[i])
    } else {
      let (num, den) = @model.nature_mult_int(nature, stat_indices[i])
      result[i] = calc_other_full(bases[i], ivs[i], evs[i], num, den)
    }
  }
  result
}

///|
/// Minimum EV (0..=252, multiple of 4) required to reach a given HP actual value,
/// given base and IV. Returns 256 sentinel if unreachable (target too high for EV 252).
///
/// Forward: actual = floor((base*2 + iv + floor(ev/4)) * 50 / 100) + 60
/// Solve:   floor((base*2+iv+q)/2) ≥ target-60
///          base*2+iv+q ≥ 2*(target-60)
///          q ≥ 2*(target-60) - base*2 - iv         where q = floor(ev/4)
pub fn ev_for_hp(base : Int, iv : Int, target : Int) -> Int {
  let needed_q = 2 * (target - 60) - base * 2 - iv
  let q = if needed_q < 0 { 0 } else { needed_q }
  let ev = q * 4
  if ev > 252 {
    return 256
  }
  // Forward-verify; if off by one due to parity, bump by +4.
  if calc_hp_full(base, iv, ev) >= target {
    return ev
  }
  let ev2 = ev + 4
  if ev2 > 252 {
    return 256
  }
  ev2
}

///|
/// Minimum EV (0..=252, multiple of 4) required to reach a given non-HP actual value
/// under the specified nature multiplier. Returns 256 sentinel if unreachable.
///
/// Forward: actual = floor((floor((base*2+iv+floor(ev/4))/2) + 5) * nature_num / nature_den)
/// Solve for minimum ev:
///   raw_min = ceil(target * nature_den / nature_num)
///   inner_floor_min = raw_min - 5
///   q_min = max(0, 2*inner_floor_min - base*2 - iv)
///   ev = q_min * 4
pub fn ev_for_non_hp(
  base : Int,
  iv : Int,
  target : Int,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  // raw_min such that floor(raw_min * num / den) >= target
  //   raw_min * num >= target * den
  //   raw_min >= ceil(target * den / num)
  let raw_min = if nature_num == nature_den {
    target
  } else {
    (target * nature_den + nature_num - 1) / nature_num
  }
  let inner_floor_min = raw_min - 5
  // floor((base*2+iv+q)/2) >= inner_floor_min
  //   base*2+iv+q >= 2*inner_floor_min
  let needed = 2 * inner_floor_min - base * 2 - iv
  let q = if needed < 0 { 0 } else { needed }
  let ev = q * 4
  if ev > 252 {
    return 256
  }
  // Forward-verify; bump by +4 if off-by-one.
  if calc_other_full(base, iv, ev, nature_num, nature_den) >= target {
    return ev
  }
  let ev2 = ev + 4
  if ev2 > 252 {
    return 256
  }
  if calc_other_full(base, iv, ev2, nature_num, nature_den) >= target {
    return ev2
  }
  // If still not reached, keep bumping (rare: nature division rounding)
  let ev3 = ev2 + 4
  if ev3 > 252 {
    return 256
  }
  ev3
}

///|
/// Reverse: given actual stat value, derive the base stat.
/// Uses algebraic inversion + forward verification with ±1 adjustment.
pub fn reverse_base_from_stat(
  actual : Int,
  iv : Int,
  ev : Int,
  is_hp : Bool,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  if is_hp {
    // actual = floor((base*2 + iv + ev/4) * 50 / 100) + 60
    // actual - 60 = floor((base*2 + iv + ev/4) / 2)
    // base = ((actual - 60) * 2 - iv - ev/4) / 2
    let inner = actual - 60
    let base = (inner * 2 - iv - ev / 4) / 2
    // forward verify and adjust
    if calc_hp_full(base, iv, ev) == actual {
      return base
    }
    if calc_hp_full(base + 1, iv, ev) == actual {
      return base + 1
    }
    if base > 0 && calc_hp_full(base - 1, iv, ev) == actual {
      return base - 1
    }
    return base
  }
  // Non-HP: undo nature first
  // actual = floor(raw * nature_num / nature_den)
  // raw = ceil(actual * nature_den / nature_num)
  let raw = if nature_num != nature_den {
    (actual * nature_den + nature_num - 1) / nature_num
  } else {
    actual
  }
  // raw = floor((base*2 + iv + ev/4) * 50 / 100) + 5
  // raw - 5 = floor((base*2 + iv + ev/4) / 2)
  let inner = raw - 5
  let base = (inner * 2 - iv - ev / 4) / 2
  // forward verify and adjust
  if calc_other_full(base, iv, ev, nature_num, nature_den) == actual {
    return base
  }
  if calc_other_full(base + 1, iv, ev, nature_num, nature_den) == actual {
    return base + 1
  }
  if base > 0 &&
    calc_other_full(base - 1, iv, ev, nature_num, nature_den) == actual {
    return base - 1
  }
  base
}

///|
/// Reverse: given Pokemon + 6 actual stats + IV, find nature + EV spread.
/// Returns all valid (Nature, evs[6]) combinations with total EV ≤ 510.
pub fn reverse_spread(
  pokemon : @model.Pokemon,
  actual_stats : FixedArray[Int],
  iv : Int,
) -> Array[(@model.Nature, FixedArray[Int])] {
  let bases : FixedArray[Int] = [
    pokemon.hp, pokemon.atk, pokemon.def_, pokemon.spa, pokemon.spd,
    pokemon.spe,
  ]
  let stat_indices : FixedArray[@model.StatIndex] = [
    HP, Atk, Def, SpA, SpD, Spe,
  ]
  let natures = @model.all_natures()
  let results : Array[(@model.Nature, FixedArray[Int])] = []
  for ni = 0; ni < natures.length(); ni = ni + 1 {
    let nature = natures[ni]
    let evs : FixedArray[Int] = FixedArray::make(6, -1)
    let mut valid = true
    for si = 0; si < 6; si = si + 1 {
      if not(valid) {
        break
      }
      let actual = actual_stats[si]
      let base = bases[si]
      if si == 0 {
        // HP: try EV values 0,4,8,...,252
        let mut found_ev = -1
        for ev_idx = 0; ev_idx <= 63; ev_idx = ev_idx + 1 {
          let ev = ev_idx * 4
          if calc_hp_full(base, iv, ev) == actual {
            found_ev = ev
            break
          }
        }
        if found_ev < 0 {
          valid = false
        } else {
          evs[si] = found_ev
        }
      } else {
        let (num, den) = @model.nature_mult_int(nature, stat_indices[si])
        let mut found_ev = -1
        for ev_idx = 0; ev_idx <= 63; ev_idx = ev_idx + 1 {
          let ev = ev_idx * 4
          if calc_other_full(base, iv, ev, num, den) == actual {
            found_ev = ev
            break
          }
        }
        if found_ev < 0 {
          valid = false
        } else {
          evs[si] = found_ev
        }
      }
    }
    if valid {
      let mut total = 0
      for si = 0; si < 6; si = si + 1 {
        total = total + evs[si]
      }
      if total <= 510 {
        results.push((nature, evs))
      }
    }
  }
  // Sort by total EV ascending
  results.sort_by(fn(a, b) {
    let (_, evs_a) = a
    let (_, evs_b) = b
    let mut sum_a = 0
    let mut sum_b = 0
    for i = 0; i < 6; i = i + 1 {
      sum_a = sum_a + evs_a[i]
      sum_b = sum_b + evs_b[i]
    }
    sum_a - sum_b
  })
  results
}

// ──────────────────────────────────────────────
// Champions SP-based stat calculations
// ──────────────────────────────────────────────

///|
/// Champions HP: base + sp + 75
pub fn calc_hp_champions(base : Int, sp : Int) -> Int {
  base + sp + 75
}

///|
/// Champions non-HP: floor((base + sp + 20) * nature_num / nature_den)
pub fn calc_other_champions(
  base : Int,
  sp : Int,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  (base + sp + 20) * nature_num / nature_den
}

///|
/// Champions stat shortcut (SP=32 default) for damage engine.
pub fn calc_stat_champions(
  base : Int,
  is_hp? : Bool = false,
  nature_boost? : Bool = true,
  custom? : Int = 0,
) -> Int {
  if custom > 0 {
    return custom
  }
  if is_hp {
    return calc_hp_champions(base, 32)
  }
  let (num, den) = if nature_boost { (11, 10) } else { (1, 1) }
  calc_other_champions(base, 32, num, den)
}

///|
/// Calculate all 6 stats for Champions.
/// sps: FixedArray of 6 SP values in HP,Atk,Def,SpA,SpD,Spe order.
pub fn calc_all_stats_champions(
  pokemon : @model.Pokemon,
  sps : FixedArray[Int],
  nature : @model.Nature,
) -> FixedArray[Int] {
  let bases : FixedArray[Int] = [
    pokemon.hp, pokemon.atk, pokemon.def_, pokemon.spa, pokemon.spd,
    pokemon.spe,
  ]
  let stat_indices : FixedArray[@model.StatIndex] = [
    HP, Atk, Def, SpA, SpD, Spe,
  ]
  let result : FixedArray[Int] = FixedArray::make(6, 0)
  for i = 0; i < 6; i = i + 1 {
    if i == 0 {
      result[i] = calc_hp_champions(bases[i], sps[i])
    } else {
      let (num, den) = @model.nature_mult_int(nature, stat_indices[i])
      result[i] = calc_other_champions(bases[i], sps[i], num, den)
    }
  }
  result
}

///|
/// Champions: minimum SP (0..=32) to reach target HP. Returns 33 if unreachable.
pub fn sp_for_hp_champions(base : Int, target : Int) -> Int {
  let sp = target - base - 75
  if sp < 0 {
    return 0
  }
  if sp > 32 {
    return 33
  }
  sp
}

///|
/// Champions: minimum SP (0..=32) to reach target non-HP stat. Returns 33 if unreachable.
pub fn sp_for_non_hp_champions(
  base : Int,
  target : Int,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  // Undo nature: raw_min such that floor(raw_min * num / den) >= target
  let raw_min = if nature_num == nature_den {
    target
  } else {
    (target * nature_den + nature_num - 1) / nature_num
  }
  // raw_min = base + sp + 20 → sp = raw_min - base - 20
  let sp = raw_min - base - 20
  if sp < 0 {
    return 0
  }
  if sp > 32 {
    return 33
  }
  // Forward-verify
  if calc_other_champions(base, sp, nature_num, nature_den) >= target {
    return sp
  }
  let sp2 = sp + 1
  if sp2 > 32 {
    return 33
  }
  sp2
}

///|
/// Champions: reverse derive base stat from actual value + SP.
pub fn reverse_base_from_stat_champions(
  actual : Int,
  sp : Int,
  is_hp : Bool,
  nature_num : Int,
  nature_den : Int,
) -> Int {
  if is_hp {
    // actual = base + sp + 75
    return actual - sp - 75
  }
  // actual = floor((base + sp + 20) * num / den)
  let raw = if nature_num != nature_den {
    (actual * nature_den + nature_num - 1) / nature_num
  } else {
    actual
  }
  let base = raw - sp - 20
  // Forward-verify with ±1
  if calc_other_champions(base, sp, nature_num, nature_den) == actual {
    return base
  }
  if calc_other_champions(base + 1, sp, nature_num, nature_den) == actual {
    return base + 1
  }
  if base > 0 &&
    calc_other_champions(base - 1, sp, nature_num, nature_den) == actual {
    return base - 1
  }
  base
}

///|
/// Champions: reverse derive nature + SP spread from actual stats.
/// Per-stat inversion (not brute-force). Total SP ≤ 66.
pub fn reverse_spread_champions(
  pokemon : @model.Pokemon,
  actual_stats : FixedArray[Int],
) -> Array[(@model.Nature, FixedArray[Int])] {
  let bases : FixedArray[Int] = [
    pokemon.hp, pokemon.atk, pokemon.def_, pokemon.spa, pokemon.spd,
    pokemon.spe,
  ]
  let stat_indices : FixedArray[@model.StatIndex] = [
    HP, Atk, Def, SpA, SpD, Spe,
  ]
  let natures = @model.all_natures()
  let results : Array[(@model.Nature, FixedArray[Int])] = []
  for ni = 0; ni < natures.length(); ni = ni + 1 {
    let nature = natures[ni]
    let sps : FixedArray[Int] = FixedArray::make(6, -1)
    let mut valid = true
    for si = 0; si < 6; si = si + 1 {
      if not(valid) {
        break
      }
      let actual = actual_stats[si]
      let base = bases[si]
      if si == 0 {
        let sp = actual - base - 75
        if sp < 0 || sp > 32 {
          valid = false
        } else if calc_hp_champions(base, sp) == actual {
          sps[si] = sp
        } else {
          valid = false
        }
      } else {
        let (num, den) = @model.nature_mult_int(nature, stat_indices[si])
        // Try direct inversion
        let raw = if num != den {
          (actual * den + num - 1) / num
        } else {
          actual
        }
        let sp_candidate = raw - base - 20
        if sp_candidate >= 0 &&
          sp_candidate <= 32 &&
          calc_other_champions(base, sp_candidate, num, den) == actual {
          sps[si] = sp_candidate
        } else {
          // Fallback: scan SP 0..32 (handles rounding edge cases)
          let mut found = -1
          for sp = 0; sp <= 32; sp = sp + 1 {
            if calc_other_champions(base, sp, num, den) == actual {
              found = sp
              break
            }
          }
          if found < 0 {
            valid = false
          } else {
            sps[si] = found
          }
        }
      }
    }
    if valid {
      let mut total = 0
      for si = 0; si < 6; si = si + 1 {
        total = total + sps[si]
      }
      if total <= 66 {
        results.push((nature, sps))
      }
    }
  }
  results.sort_by(fn(a, b) {
    let (_, sps_a) = a
    let (_, sps_b) = b
    let mut sum_a = 0
    let mut sum_b = 0
    for i = 0; i < 6; i = i + 1 {
      sum_a = sum_a + sps_a[i]
      sum_b = sum_b + sps_b[i]
    }
    sum_a - sum_b
  })
  results
}
