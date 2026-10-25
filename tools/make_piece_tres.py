"""Writes PieceDef .tres files for pieces described below (the third batch of
custom pieces). Run from the project folder:  python tools/make_piece_tres.py

Each rule: (directions, max_steps, mode, extra fields). Modes: 0 move or
capture, 1 move only, 2 capture only. Directions are (files, ranks) from the
owner's side, positive ranks = towards the opponent.
"""
import io

ORTHO = [(1, 0), (-1, 0), (0, 1), (0, -1)]
DIAG = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
ALL8 = ORTHO + DIAG
TWO_AWAY = [(2 * x, 2 * y) for x, y in ALL8]

PIECES = {
    "princess": dict(name="Princess", symbol="PR", value=8.5, rules=[(ALL8, 4, 0, {})]),
    "galleon": dict(name="Galleon", symbol="GA", value=3, rules=[
        (ALL8, 0, 1, {}),
        (DIAG + [(1, 0), (-1, 0)], 1, 2, {}),
    ]),
    "catapult": dict(name="Catapult", symbol="CT", value=3, keywords=1, rules=[
        (ALL8, 1, 1, {}),
        (TWO_AWAY, 1, 2, {}),
    ]),
    "assassin": dict(name="Assassin", symbol="AS", value=0.5, rules=[
        ([(0, 1)], 2, 1, {}),
        ([(1, 1), (-1, 1)], 1, 1, {}),
        ([(0, -1), (1, -1), (-1, -1)], 1, 2, {}),
    ]),
    # Batch 2 (rules in the engine: see PieceDef.blocks_jumps, shield_on_capture,
    # protects and decoy).
    # Keywords: 1 Jump, 2 Castle, 4 Promote, 8 Shield, 16 Wall.
    "parapet": dict(name="Parapet", symbol="PA", value=2.5, keywords=2 | 16, rules=[
        ([(1, 0), (-1, 0)], 0, 0, {}),
        (DIAG, 1, 0, {}),
    ],
        special_rule="Enemy pieces can't jump over the Parapet."),
    "vampire": dict(name="Vampire", symbol="V", value=6.5, rules=[
        ([(1, 0), (-1, 0), (0, -1)], 0, 0, {}),
        ([(1, 1), (-1, 1)], 1, 0, {}),
    ], extra={"shield_on_capture": "true"},
        special_rule="Whenever the Vampire captures a piece, if the Vampire didn't have one, it gains {Shield}."),
    "squire": dict(name="Squire", symbol="SQ", value=4, rules=[
        (ORTHO, 2, 0, {}),
        (DIAG, 1, 0, {}),
    ], extra={"protects": 'Array[String](["knight"])'},
        special_rule="Your Knights that are within the Squire's move range can't be captured."),
    "jester": dict(name="Jester", symbol="J", value=3.5, rules=[
        (ALL8, 2, 1, {}),
        (ALL8, 1, 2, {}),
    ], extra={"decoy": "true"},
        special_rule="If an enemy piece would capture one of your non-*Pawn* pieces on a square within the Jester's move range, the Jester and your piece swap places first. If more than one Jester could take the hit, the attacking player chooses which."),
    # Batch 3: abilities (PieceDef.Ability HAUNT = 3, SONG_OF_SLUMBER = 4,
    # FULL_MOON = 5). Colours are the ability's gradient, left to right.
    "ghost": dict(name="Ghost", symbol="G", value=3, rules=[
        (DIAG, 1, 0, {}),
        ([(0, 1)], 1, 0, {}),
    ], ability=3, ability_name="Haunt", colors=["#A8D4F5", "#F0F8FF"],
        ability_text="Place the Ghost from the Graveyard onto any open square."),
    "bard": dict(name="Bard", symbol="BD", value=3.5, rules=[
        (DIAG, 4, 0, {}),
    ], ability=4, ability_name="Song of Slumber", colors=["#F5C542", "#C46A12"],
        ability_text="Put an enemy non-*King* piece within the Bard's move range to sleep during your opponent's next turn. (It can't take actions.)"),
    "werewolf": dict(name="Werewolf", symbol="WW", value=3.5, rules=[
        (DIAG, 1, 0, {}),
        ([(0, 1)], 1, 0, {}),
    ], ability=5, ability_name="Full Moon", colors=["#F5F2E3", "#8E959E"], glow=["#789EFF", "#283199"], transforms_into="forms/werewolf_wolf",
        extra={"form_name": '"Human"'},
        ability_text="The Werewolf transforms from human form into wolf form."),
    # The Werewolf after Full Moon. Kept in forms/ so the army builder doesn't offer it.
    "werewolf_wolf": dict(name="Werewolf", symbol="WF", value=3.5, path="forms/werewolf_wolf", rules=[
        ([(1, 0), (-1, 0), (0, -1)], 1, 0, {}),
        ([(1, 1), (-1, 1), (0, 1)], 2, 0, {}),
    ], extra={"form_name": '"Wolf"'},
        special_rule="A Werewolf that has used its Full Moon: a wolf for the rest of the game."),
}


def color_list(colors):
    values = []
    for c in colors:
        c = c.lstrip("#")
        values += ["%.3g" % (int(c[i:i + 2], 16) / 255) for i in (0, 2, 4)] + ["1"]
    return "PackedColorArray(%s)" % ", ".join(values)


def vec_list(dirs):
    return "Array[Vector2i]([%s])" % ", ".join("Vector2i(%d, %d)" % d for d in dirs)


def write(piece_id, spec):
    lines = ['[gd_resource type="Resource" script_class="PieceDef" format=3]', "",
             '[ext_resource type="Script" path="res://core/move_rule.gd" id="1_rule"]',
             '[ext_resource type="Script" path="res://core/piece_def.gd" id="2_def"]']
    if spec.get("transforms_into"):
        lines.append('[ext_resource type="Resource" path="res://data/pieces/%s.tres" id="3_form"]' % spec["transforms_into"])
    lines.append("")
    names = []
    for i, (dirs, steps, mode, extra) in enumerate(spec["rules"]):
        name = "Resource_rule%d" % (i + 1)
        names.append(name)
        lines.append('[sub_resource type="Resource" id="%s"]' % name)
        lines.append('script = ExtResource("1_rule")')
        lines.append("directions = " + vec_list(dirs))
        lines.append("max_steps = %d" % steps)
        if mode:
            lines.append("mode = %d" % mode)
        for key, value in extra.items():
            lines.append("%s = %s" % (key, value))
        lines.append("")
    lines += ["[resource]", 'script = ExtResource("2_def")', 'id = "%s"' % piece_id,
              'display_name = "%s"' % spec["name"], 'symbol = "%s"' % spec["symbol"],
              "value = %s" % spec["value"],
              'move_rules = Array[ExtResource("1_rule")]([%s])' % ", ".join('SubResource("%s")' % n for n in names)]
    if spec.get("types"):
        lines.append("types = %d" % spec["types"])
    if spec.get("keywords"):
        lines.append("keywords = %d" % spec["keywords"])
    for key, value in spec.get("extra", {}).items():
        lines.append("%s = %s" % (key, value))
    if spec.get("ability"):
        lines.append("ability = %d" % spec["ability"])
    if spec.get("transforms_into"):
        lines.append('transforms_into = ExtResource("3_form")')
    if spec.get("colors"):
        lines.append("ability_colors = " + color_list(spec["colors"]))
    if spec.get("glow"):
        lines.append("glow_colors = " + color_list(spec["glow"]))
    for key in ("special_rule", "ability_name", "ability_text"):
        if spec.get(key):
            lines.append('%s = "%s"' % (key, spec[key].replace('"', '\\"')))
    path = "data/pieces/%s.tres" % spec.get("path", piece_id)
    io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    import sys
    wanted = sys.argv[1:] or list(PIECES)
    for piece_id, spec in PIECES.items():
        if piece_id not in wanted:
            continue
        write(piece_id, spec)
        print("wrote", piece_id)
