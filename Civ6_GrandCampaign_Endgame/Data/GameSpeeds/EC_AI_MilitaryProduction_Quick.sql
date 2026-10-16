-- Round 48: conservative speed-tiered military production for Quick games.
INSERT OR IGNORE INTO Modifiers
  (ModifierId, ModifierType, OwnerRequirementSetId)
VALUES
  ('EC_AI_MILITARY_SPEED_QUICK',
   'MODIFIER_PLAYER_CITIES_ADJUST_MILITARY_UNITS_PRODUCTION',
   'EC_AI_MILITARY_OWNER');

INSERT OR IGNORE INTO ModifierArguments (ModifierId, Name, Value)
VALUES ('EC_AI_MILITARY_SPEED_QUICK', 'Amount', 5);

INSERT OR IGNORE INTO TraitModifiers (TraitType, ModifierId)
VALUES ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_SPEED_QUICK');
