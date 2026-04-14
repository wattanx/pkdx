///|
/// Query all moves a Pokemon can learn (level-up + TM).
/// For champions version, reads from champions_learnset; other versions
/// use local_pokedex_waza + local_pokedex_waza_machine.
pub fn query_moves(
  db : Db,
  global_no : String,
  version : String,
  include_inactive~ : Bool = false,
) -> Result[Array[@model.Move], String] {
  if version == "champions" {
    query_moves_champions(db, global_no, include_inactive)
  } else {
    query_moves_legacy(db, global_no, version)
  }
}

///|
fn query_moves_champions(
  db : Db,
  global_no : String,
  include_inactive : Bool,
) -> Result[Array[@model.Move], String] {
  let gno = normalize_global_no(global_no)
  let state_filter = if include_inactive {
    ""
  } else {
    " AND cl.state = 'active'"
  }
  // learn_method column returns 'active' or 'inactive' so callers/formatters
  // can distinguish confiscated moves. For legacy versions this stays as
  // 'basic' / 'TM' — a small but visible shift in semantics worth noting
  // if you touch the formatter.
  let sql_head =
    #|SELECT DISTINCT wl.name AS move_name, w.type, w.category,
    #|       w.power, w.accuracy, w.pp, cl.state AS learn_method
    #|FROM champions_learnset cl
    #|JOIN local_waza w ON cl.waza = w.waza AND w.version = 'Champions'
    #|JOIN local_waza_language wl ON cl.waza = wl.waza
    #|  AND wl.version = 'Champions' AND wl.language = 'jpn'
    #|WHERE cl.globalNo = ?
    #|  AND COALESCE(cl.form, '') = '' AND COALESCE(cl.region, '') = ''
    #|  AND COALESCE(cl.mega_evolution, '') = '' AND COALESCE(cl.gigantamax, '') = ''
  let sql_tail =
    #|ORDER BY power DESC
  let sql = sql_head + state_filter + "\n" + sql_tail
  collect_moves_rows(db, sql, [gno])
}

///|
fn query_moves_legacy(
  db : Db,
  global_no : String,
  version : String,
) -> Result[Array[@model.Move], String] {
  let waza_ver = to_waza_version(version)
  let gno = normalize_global_no(global_no)
  let sql =
    #|SELECT DISTINCT wl.name AS move_name, w.type, w.category,
    #|       w.power, w.accuracy, w.pp, pw.conditions AS learn_method
    #|FROM local_pokedex_waza pw
    #|JOIN local_waza w ON pw.waza = w.waza AND w.version = ?
    #|JOIN local_waza_language wl ON pw.waza = wl.waza
    #|  AND wl.version = ? AND wl.language = 'jpn'
    #|WHERE pw.globalNo = ? AND pw.version = ?
    #|UNION
    #|SELECT DISTINCT wl.name AS move_name, w.type, w.category,
    #|       w.power, w.accuracy, w.pp, 'TM' AS learn_method
    #|FROM local_pokedex_waza_machine pm
    #|JOIN local_waza_machine wm ON pm.machine_no = wm.waza AND wm.version = ?
    #|JOIN local_waza w ON wm.machine_no = w.waza AND w.version = ?
    #|JOIN local_waza_language wl ON w.waza = wl.waza
    #|  AND wl.version = ? AND wl.language = 'jpn'
    #|WHERE pm.globalNo = ? AND pm.version = ?
    #|  AND COALESCE(pm.form, '') = '' AND COALESCE(pm.region, '') = ''
    #|ORDER BY power DESC
  let binds = [
    waza_ver, waza_ver, gno, waza_ver, waza_ver, waza_ver, waza_ver, gno, waza_ver,
  ]
  collect_moves_rows(db, sql, binds)
}

///|
fn collect_moves_rows(
  db : Db,
  sql : String,
  binds : Array[String],
) -> Result[Array[@model.Move], String] {
  let rows = match query(db, sql, binds) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let moves : Array[@model.Move] = []
  for i = 0; i < rows.length(); i = i + 1 {
    let r = rows[i]
    moves.push(@model.Move::{
      name: r[0],
      type_: r[1],
      category: @model.category_from_jp(r[2]),
      power: parse_int(r[3]),
      accuracy: parse_int(r[4]),
      pp: parse_int(r[5]),
      learn_method: r[6],
    })
  }
  Ok(moves)
}
