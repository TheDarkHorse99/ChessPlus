extends SceneTree

## Writes the online referee's copy of the game's rules (RuleSet) and its test
## cases. Run it after any change to the pieces or army rules, then deploy the
## referee (tools/deploy_referee.sh) BEFORE deploying the game, so the referee
## knows the new version when the new game first asks for it.
##
##   "<godot console exe>" --headless --path . -s res://tools/make_rule_set.gd
##
## Writes into server/supabase/functions/referee/:
##   rules/<version>.json   the rule set (old versions stay, for games started
##                          on them)
##   rules.ts               the list of rule sets the referee knows
##   test_cases.json        army pairs with what the game itself makes of them:
##                          the army problems, the starting position Plusfish is
##                          given, and a whole game played by the game's own
##                          rules engine with its ending; the referee's tests
##                          (referee_test.ts) check it agrees

const FOLDER := "res://server/supabase/functions/referee/"
const OUTCOMES := ["none", "checkmate", "stalemate", "fifty_moves", "repetition", "insufficient_material", "king_exposed", "seventy_five_moves"]

## Army pairs to check, as army text (Plusfish's form: back row / front row,
## files a-h, two-letter symbols in brackets, digits for gaps), and whether
## each is turned round for Black.
const PAIRS := [
	["RNBQKBNR/PPPPPPPP", false, "RNBQKBNR/PPPPPPPP", false],
	["(NC)(WW)ENKQPA/GB(AS)(CV)PG1(AS)", true, "1(WW)GK(NC)(CV)(GA)R/(AS)BB(CV)GE(PD)L", true],
	["QE(WW)1KN(NC)(RM)/(AS)APB(BR)(PD)G(AS)", true, "P(CV)NCK(BR)1B/(AS)G(BR)LV(RM)B(AS)", true],
	["1Q1KGE(NC)C/B(AS)BG(BR)(AS)(PD)A", true, "RNBQKBNR/PPPPPPPP", false],
	["(PA)(GA)V(PR)K(BR)N(WW)/PPPPPPPP", true, "J(SQ)(CT)KBMMB/PPPPV1PE", true],
	["(CH)(RO)(RO)KE(SQ)C(PD)/PNP(RM)PPPL", true, "(CT)AGK(NC)(PR)WC/1(AS)P4(PD)", true],
	["BP(AS)1K(WW)WB/(PD)A(BD)(RM)(CV)A1(AS)", true, "Q(NC)(NC)KVENJ/(AS)PPPPPPP", true],
]
## Games with known endings: [white army, mirror, black army, mirror, moves].
const SHORT_GAMES := [
	# The fastest checkmate.
	["RNBQKBNR/PPPPPPPP", false, "RNBQKBNR/PPPPPPPP", false, ["f2-f3", "e7-e5", "g2-g4", "d8-h4"]],
	# A Lance looking straight at Black's king before any move: King exposed.
	["RNBQKBNR/PPPPLPPP", false, "RNBQKBNR/PPPP1PPP", false, []],
]
## Armies that break the rules, with the problems the game finds.
const BROKEN := [
	"QQQKQQQQ/PPPPPPPP",
	"RNBQ1BNR/PPPPKPPP",
	"RNBQKBNR/PPPPPPPP/PPPPPPPP",
]

func _initialize() -> void:
	var version := RuleSet.version()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER + "rules"))
	_write(FOLDER + "rules/%s.json" % version, RuleSet.text() + "\n")
	_write_index()
	_write(FOLDER + "test_cases.json", JSON.stringify(_test_cases(version), "\t", true) + "\n")
	print("Rule set %s written (%d piece types)." % [version, RuleSet.data().pieces.size()])
	quit()

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

## rules.ts: every rule set file, by version.
func _write_index() -> void:
	var versions := []
	for file in DirAccess.get_files_at(FOLDER + "rules"):
		if file.ends_with(".json"):
			versions.append(file.get_basename())
	versions.sort()
	var lines := ["// Written by tools/make_rule_set.gd: every rule set the referee knows, by version.", ""]
	for v: String in versions:
		lines.append('import r_%s from "./rules/%s.json" with { type: "json" };' % [v, v])
	lines.append("")
	lines.append("export const RULE_SETS: Record<string, RuleSetData> = {")
	for v: String in versions:
		lines.append('  "%s": r_%s as unknown as RuleSetData,' % [v, v])
	lines.append("};")
	lines.append("")
	lines.append('import type { RuleSetData } from "./referee.ts";')
	_write(FOLDER + "rules.ts", "\n".join(lines) + "\n")

func _test_cases(version: String) -> Dictionary:
	var defs := {}
	for def in PieceCatalog.all_defs():
		defs[def.symbol] = def
	var rules := StandardSetup.create_rules()
	var cases := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for pair in PAIRS:
		var white := _army(pair[0], pair[1], defs)
		var black := _army(pair[2], pair[3], defs)
		var start := ArmySetup.create_game(white, black, rules)
		# A whole game by the game's own engine: random legal moves (captures
		# preferred, so games end), up to 120 plies.
		var state := ArmySetup.create_game(white, black, rules)
		var moves := []
		while state.outcome() == GameState.Outcome.NONE and moves.size() < 120:
			var legal := state.moves()
			var captures := legal.filter(func(m: Move) -> bool: return m.is_capture())
			var pool: Array = captures if not captures.is_empty() and rng.randf() < 0.7 else legal
			var move: Move = pool[rng.randi_range(0, pool.size() - 1)]
			moves.append(move.to_text())
			state.make_move(move)
		cases.append({
			"white": SavedGame.army_to_dict(white),
			"black": SavedGame.army_to_dict(black),
			"white_problems": Array(RuleText.plain_lines(white.problems(rules, 8))),
			"black_problems": Array(RuleText.plain_lines(black.problems(rules, 8))),
			"start": PlusfishLink.position_for(start),
			"supported": PlusfishLink.supports(start),
			"moves": moves,
			"outcome": OUTCOMES[state.outcome()],
		})
	for game in SHORT_GAMES:
		var white := _army(game[0], game[1], defs)
		var black := _army(game[2], game[3], defs)
		var start := ArmySetup.create_game(white, black, rules)
		var state := ArmySetup.create_game(white, black, rules)
		for text: String in game[4]:
			state.make_move(state.find_move(text))
		cases.append({
			"white": SavedGame.army_to_dict(white), "black": SavedGame.army_to_dict(black),
			"white_problems": Array(RuleText.plain_lines(white.problems(rules, 8))), "black_problems": Array(RuleText.plain_lines(black.problems(rules, 8))),
			"start": PlusfishLink.position_for(start), "supported": PlusfishLink.supports(start),
			"moves": game[4], "outcome": OUTCOMES[state.outcome()],
		})
	var broken := []
	for text: String in BROKEN:
		var army := _army(text, true, defs)
		if army == null:
			continue
		broken.append({"army": SavedGame.army_to_dict(army), "problems": Array(RuleText.plain_lines(army.problems(rules, 8)))})
	return {"version": version, "games": cases, "broken": broken}

## An army from its text (rows from the back; extra rows make it break the
## starting-rows rule).
func _army(text: String, mirror: bool, defs: Dictionary) -> Army:
	var army := Army.new()
	army.army_name = text
	army.mirror_for_black = mirror
	var row := 0
	for part in text.split("/"):
		var file := 0
		var i := 0
		while i < part.length():
			var c := part[i]
			if c.is_valid_int():
				file += int(c)
				i += 1
				continue
			var symbol := c
			if c == "(":
				var end := part.find(")", i)
				symbol = part.substr(i + 1, end - i - 1)
				i = end
			army.pieces.append(ArmyPiece.make(defs[symbol], Vector2i(file, row)))
			file += 1
			i += 1
		row += 1
	return army
