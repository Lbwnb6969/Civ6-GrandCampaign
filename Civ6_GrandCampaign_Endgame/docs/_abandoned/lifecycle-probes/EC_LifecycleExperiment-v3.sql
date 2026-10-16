-- Opt-in native probe only. No release gameplay enables this action yet.
-- Test whether the engine's default defeat requirement can retain an
-- archived player with no cities or units, preserving the original identity.
INSERT INTO Types (Type, Kind) VALUES ('CIVIC_EC_ARCHIVE_STATUS', 'KIND_CIVIC');
INSERT INTO Civics (CivicType, Name, Cost, EraType, UITreeRow, AdvisorType)
VALUES ('CIVIC_EC_ARCHIVE_STATUS', 'LOC_EC_ARCHIVE_STATUS', 1000000, 'ERA_INFORMATION', 10, 'ADVISOR_GENERIC');
INSERT INTO CivicPrereqs (Civic, PrereqCivic)
VALUES ('CIVIC_EC_ARCHIVE_STATUS', 'CIVIC_NUCLEAR_PROGRAM');
INSERT INTO Civics_XP2 (CivicType, HiddenUntilPrereqComplete)
VALUES ('CIVIC_EC_ARCHIVE_STATUS', 1);
INSERT INTO CivicQuotes (CivicType, Quote)
SELECT 'CIVIC_EC_ARCHIVE_STATUS', Quote FROM CivicQuotes WHERE CivicType='CIVIC_FUTURE_CIVIC';
INSERT INTO Requirements (RequirementId, RequirementType, Inverse)
VALUES ('EC_PLAYER_NOT_ARCHIVED_PROBE', 'REQUIREMENT_PLAYER_HAS_CIVIC', 1);
INSERT INTO RequirementArguments (RequirementId, Name, Value)
VALUES ('EC_PLAYER_NOT_ARCHIVED_PROBE', 'CivicType', 'CIVIC_EC_ARCHIVE_STATUS');
INSERT INTO RequirementSetRequirements (RequirementSetId, RequirementId)
VALUES ('DEFAULT_DEFEAT_REQUIREMENTS', 'EC_PLAYER_NOT_ARCHIVED_PROBE');
