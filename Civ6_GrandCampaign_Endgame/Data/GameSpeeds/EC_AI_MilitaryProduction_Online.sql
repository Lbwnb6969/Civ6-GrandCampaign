-- Round 48: the speed-specific slice is loaded only when the modinfo
-- criterion matches GAMESPEED_ONLINE and the AI production test is enabled.
INSERT OR IGNORE INTO Modifiers
  (ModifierId, ModifierType, OwnerRequirementSetId)
VALUES
  ('EC_AI_MILITARY_SPEED_ONLINE',
   'MODIFIER_PLAYER_CITIES_ADJUST_MILITARY_UNITS_PRODUCTION',
   'EC_AI_MILITARY_OWNER');

INSERT OR IGNORE INTO ModifierArguments (ModifierId, Name, Value)
VALUES ('EC_AI_MILITARY_SPEED_ONLINE', 'Amount', 4);

INSERT OR IGNORE INTO TraitModifiers (TraitType, ModifierId)
VALUES ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_SPEED_ONLINE');
