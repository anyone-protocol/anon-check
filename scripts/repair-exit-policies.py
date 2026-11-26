#!/usr/bin/env python3

# The check server calls log.Fatal if data/exit-policies is missing or holds a
# malformed line, so a truncated file keeps it from ever starting again. A kill
# during a rewrite used to leave exactly that. Drop the incomplete lines and let
# the server come up on whatever is still good.

import json
import os
import sys

PATH = "data/exit-policies"

if not os.path.exists(PATH):
    open(PATH, "w").close()
    print("exit-policies missing, seeded empty")
    sys.exit(0)

good = []
bad = 0

with open(PATH) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            json.loads(line)
        except ValueError:
            bad += 1
            continue
        good.append(line)

if bad:
    tmp = PATH + ".repair"
    with open(tmp, "w") as f:
        for line in good:
            f.write(line + "\n")
    os.replace(tmp, PATH)
    print(f"exit-policies repaired: dropped {bad} malformed line(s), kept {len(good)}")
else:
    print(f"exit-policies ok: {len(good)} entries")
