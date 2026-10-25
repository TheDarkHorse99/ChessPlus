"""Round 24 art options (white versions, for choosing): the three pawn-type
pieces Mac designed on 25 Oct 2026. Grunt = the Cburnett pawn in a helmet
(bare-headed once its shield breaks), Abatis = two sharpened stakes crossing
near their tips, Vassal = the pawn in a cloak. Single colour like the Pawn.

Cburnett style: 45x45 canvas, 1.5 black outline, white fill. Run from this
folder:  python make_round24.py   then render with tools/render_options.gd.
"""
import math

HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="45" height="45" viewBox="0 0 45 45">'
        '<g stroke="#000" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="#fff">')
TAIL = "</g></svg>\n"

# The Cburnett pawn (Chess_plt45.svg): ball head centred (22.5,13) r 4, collar
# at y 15-16.5, shoulders round (22.5,21), base from y 26 to 39.5.
PAWN = ('<path d="m 22.5,9 c -2.21,0 -4,1.79 -4,4 0,0.89 0.29,1.71 0.78,2.38 C 17.33,16.5 16,18.59 16,21 '
        'c 0,2.03 0.94,3.84 2.41,5.03 C 15.41,27.09 11,31.58 11,39.5 H 34 C 34,31.58 29.59,27.09 26.59,26.03 '
        '28.06,24.84 29,23.03 29,21 29,18.59 27.67,16.5 25.72,15.38 26.21,14.71 26.5,13.89 26.5,13 c 0,-2.21 -1.79,-4 -4,-4 z"/>')


def mirror(body):
    return '<g transform="translate(45,0) scale(-1,1)">%s</g>' % body


OPTIONS = {}

# --- Grunt: helmets sit on the ball head. ------------------------------------
KETTLE_DOME = '<path d="M 16.3,13.3 C 16.3,8.9 19,6.4 22.5,6.4 C 26,6.4 28.7,8.9 28.7,13.3 Z"/>'
KETTLE_BRIM = '<path d="M 14,13.3 L 31,13.3" fill="none" stroke-width="2.6"/>'
OPTIONS["grunt_kettle"] = PAWN + KETTLE_DOME + KETTLE_BRIM
OPTIONS["grunt_kettle_knob"] = PAWN + KETTLE_DOME + KETTLE_BRIM + '<circle cx="22.5" cy="6.1" r="1.4"/>'
# A conical helm with a nose bar.
OPTIONS["grunt_nasal"] = (PAWN
    + '<path d="M 16.8,13.8 C 16.8,8.4 19.6,5.2 22.5,4.6 C 25.4,5.2 28.2,8.4 28.2,13.8 Z"/>'
    + '<path d="M 16.8,13.8 L 28.2,13.8" fill="none" stroke-width="2"/>'
    + '<path d="M 22.5,14.8 L 22.5,17.4" fill="none" stroke-width="2.2"/>')
# A round helm with cheek guards reaching the collar.
CHEEK_LEFT = '<path d="M 16.5,13.5 C 16,15.6 16.6,17.1 18.4,17.7 L 19.5,14.2 Z"/>'
OPTIONS["grunt_cheek_guards"] = (PAWN
    + '<path d="M 16.5,13.5 C 16.5,8.8 19.3,6.4 22.5,6.4 C 25.7,6.4 28.5,8.8 28.5,13.5 Z"/>'
    + CHEEK_LEFT + mirror(CHEEK_LEFT))
# Once the shield breaks: bare-headed. Plain (the Pawn's own shape), or with a
# neck band so it still reads as a Grunt.
OPTIONS["grunt_wounded_plain"] = PAWN
OPTIONS["grunt_wounded_band"] = PAWN + '<path d="M 17.6,16.4 C 19.2,17.9 25.8,17.9 27.4,16.4" fill="none" stroke-width="1.8"/>'


# --- Abatis: two sharpened stakes crossing near their tips. ---------------------
def stake(x0, y0, x1, y1, w, sharp=0.22):
    """A stake from (x0,y0) to the point (x1,y1), w wide, sharpened over the last part."""
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux
    sx, sy = x0 + dx * (1 - sharp), y0 + dy * (1 - sharp)
    pts = [(x0 + px * w / 2, y0 + py * w / 2), (sx + px * w / 2, sy + py * w / 2), (x1, y1),
           (sx - px * w / 2, sy - py * w / 2), (x0 - px * w / 2, y0 - py * w / 2)]
    return '<path d="M %s Z"/>' % " L ".join("%.2f,%.2f" % p for p in pts)


HIGH = stake(10, 39.5, 26.5, 4.5, 5) + stake(35, 39.5, 18.5, 4.5, 5)   # cross at about y 13
LASHING = ('<path d="M 18.6,11.6 C 20,13.1 25,13.1 26.4,11.6 L 27,15.9 C 25.6,17.4 19.4,17.4 18,15.9 Z"/>'
           '<path d="M 18.3,13.7 C 19.8,15.1 25.2,15.1 26.7,13.7" fill="none" stroke-width="1.1"/>')
MOUND = '<path d="M 6.5,39.5 C 8,34.8 37,34.8 38.5,39.5 Z"/>'
OPTIONS["abatis_cross_high"] = HIGH
OPTIONS["abatis_cross_high_lashed"] = HIGH + LASHING
OPTIONS["abatis_cross_high_mound"] = MOUND + HIGH + LASHING
OPTIONS["abatis_cross_middle"] = stake(8, 39.5, 33, 5.5, 5) + stake(37, 39.5, 12, 5.5, 5)   # cross at about y 22


# --- Vassal: the pawn in a cloak. -----------------------------------------------
# Cloak open at the front, the pawn's body showing between the two halves.
CLOAK_LEFT = '<path d="M 22.5,15.8 C 18.2,16.1 15.2,19 14.4,23 C 13,29 11.6,34 10,39.5 L 16.2,39.5 C 16.6,33 17.2,27 19.2,22.6 Z"/>'
COLLAR = '<path d="M 17.8,17.6 C 19.6,15.9 25.4,15.9 27.2,17.6" fill="none"/>'
OPTIONS["vassal_cloak_open"] = PAWN + CLOAK_LEFT + mirror(CLOAK_LEFT) + COLLAR
OPTIONS["vassal_cloak_open_clasp"] = PAWN + CLOAK_LEFT + mirror(CLOAK_LEFT) + COLLAR + '<circle cx="22.5" cy="17.4" r="1.4"/>'
# Cloak closed over the whole body, with folds.
OPTIONS["vassal_cloak_closed"] = (PAWN
    + '<path d="M 22.5,15.8 C 17.5,16.3 13.6,21 10.5,39.5 L 34.5,39.5 C 31.4,21 27.5,16.3 22.5,15.8 Z"/>'
    + COLLAR
    + '<path d="M 17.6,21.5 C 15.6,27 14.3,33 13.6,39.5 M 27.4,21.5 C 29.4,27 30.7,33 31.4,39.5" fill="none" stroke-width="1.1"/>')
# Hood up over the head, the face showing in the opening.
OPTIONS["vassal_hood_up"] = (PAWN + CLOAK_LEFT + mirror(CLOAK_LEFT)
    + '<path d="M 22.5,5.2 C 17.3,5.2 15.3,9.6 15.8,13.6 C 16.2,15.8 17.2,17 18.3,17.6 L 26.7,17.6 C 27.8,17 28.8,15.8 29.2,13.6 C 29.7,9.6 27.7,5.2 22.5,5.2 Z"/>'
    + '<circle cx="22.5" cy="13" r="3.3"/>')

for name, body in OPTIONS.items():
    with open("white_%s.svg" % name, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEAD + body + TAIL)
print("wrote %d options" % len(OPTIONS))
