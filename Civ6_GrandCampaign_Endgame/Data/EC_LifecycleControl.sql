-- Opt-in native probe only. No release gameplay enables this action yet.
-- Test whether the engine's default defeat requirement can retain an
-- archived player with no cities or units, preserving the original identity.
-- Control: use a vanilla civic to isolate defeat-set handling from custom
-- civic-tree construction. This is a disposable probe, not a release rule.
INSERT INTO Requirements (RequirementId, RequirementType, Inverse)
VALUES ('EC_PLAYER_NOT_ARCHIVED_PROBE', 'REQUIREMENT_PLAYER_HAS_CIVIC', 1);
INSERT INTO RequirementArguments (RequirementId, Name, Value)
VALUES ('EC_PLAYER_NOT_ARCHIVED_PROBE', 'CivicType', 'CIVIC_CODE_OF_LAWS');
INSERT INTO RequirementSetRequirements (RequirementSetId, RequirementId)
VALUES ('DEFAULT_DEFEAT_REQUIREMENTS', 'EC_PLAYER_NOT_ARCHIVED_PROBE');
