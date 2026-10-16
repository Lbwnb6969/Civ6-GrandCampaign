-- Opt-in native probe only. No release gameplay enables this action yet.
-- Test whether the engine's default defeat requirement can retain an
-- archived player with no cities or units, preserving the original identity.
-- Ancient era avoids granting a later era to archived civilizations. Keep
-- the node within the native civic-tree row bounds [-3, 3]. This is still
-- a disposable probe until research/score/era side effects are verified.
INSERT OR IGNORE INTO Types (Type, Kind) VALUES ('CIVIC_EC_ARCHIVE_STATUS', 'KIND_CIVIC');
INSERT OR IGNORE INTO Civics (CivicType, Name, Cost, EraType, UITreeRow, AdvisorType)
VALUES ('CIVIC_EC_ARCHIVE_STATUS', 'LOC_EC_ARCHIVE_STATUS', 1000000, 'ERA_ANCIENT', -3, 'ADVISOR_GENERIC');
INSERT OR IGNORE INTO CivicPrereqs (Civic, PrereqCivic)
VALUES ('CIVIC_EC_ARCHIVE_STATUS', 'CIVIC_CODE_OF_LAWS');
INSERT OR IGNORE INTO Civics_XP2 (CivicType, HiddenUntilPrereqComplete)
VALUES ('CIVIC_EC_ARCHIVE_STATUS', 1);
INSERT OR IGNORE INTO CivicQuotes (CivicType, Quote)
SELECT 'CIVIC_EC_ARCHIVE_STATUS', Quote FROM CivicQuotes WHERE CivicType='CIVIC_CODE_OF_LAWS';
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType, Inverse)
VALUES ('EC_PLAYER_NOT_ARCHIVED_PROBE', 'REQUIREMENT_PLAYER_HAS_CIVIC', 1);
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
VALUES ('EC_PLAYER_NOT_ARCHIVED_PROBE', 'CivicType', 'CIVIC_EC_ARCHIVE_STATUS');
INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
VALUES ('DEFAULT_DEFEAT_REQUIREMENTS', 'EC_PLAYER_NOT_ARCHIVED_PROBE');
