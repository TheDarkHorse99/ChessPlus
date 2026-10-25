// Written by tools/make_rule_set.gd: every rule set the referee knows, by version.

import r_57a042eab440 from "./rules/57a042eab440.json" with { type: "json" };
import r_6ab1c86a6654 from "./rules/6ab1c86a6654.json" with { type: "json" };
import r_b5eaefcc22f2 from "./rules/b5eaefcc22f2.json" with { type: "json" };
import r_d39187eae1b4 from "./rules/d39187eae1b4.json" with { type: "json" };

export const RULE_SETS: Record<string, RuleSetData> = {
  "57a042eab440": r_57a042eab440 as unknown as RuleSetData,
  "6ab1c86a6654": r_6ab1c86a6654 as unknown as RuleSetData,
  "b5eaefcc22f2": r_b5eaefcc22f2 as unknown as RuleSetData,
  "d39187eae1b4": r_d39187eae1b4 as unknown as RuleSetData,
};

import type { RuleSetData } from "./referee.ts";
