-- Opt-in native lifecycle. A non-generating bonus resource preserves the
-- original player while archived, without granting civics, eras or points.
-- New test games only; old civic-marker saves need their Git checkpoint.
INSERT OR IGNORE INTO Types(Type,Kind) VALUES('RESOURCE_EC_ARCHIVE_STATUS','KIND_RESOURCE');
INSERT OR IGNORE INTO Resources(ResourceType,Name,ResourceClassType,Frequency,SeaFrequency)
VALUES('RESOURCE_EC_ARCHIVE_STATUS','LOC_EC_ARCHIVE_STATUS','RESOURCECLASS_BONUS',0,0);
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType, Inverse)
VALUES ('EC_PLAYER_NOT_ARCHIVED_RESOURCE', 'REQUIREMENT_PLAYER_HAS_RESOURCE_OWNED', 1);
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
VALUES ('EC_PLAYER_NOT_ARCHIVED_RESOURCE', 'ResourceType', 'RESOURCE_EC_ARCHIVE_STATUS');
INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
VALUES ('DEFAULT_DEFEAT_REQUIREMENTS', 'EC_PLAYER_NOT_ARCHIVED_RESOURCE');
-- DEFAULT_DEFEAT_REQUIREMENT can remain satisfied after TransferCity returns
-- an archived player's city (native 569/570/577). Keep that native rule, but
-- also require a current zero-city count before it can defeat the player.
INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType, Inverse)
VALUES ('EC_PLAYER_CURRENTLY_HAS_NO_CITIES', 'REQUIREMENT_PLAYER_HAS_AT_LEAST_NUMBER_CITIES', 1);
INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
VALUES ('EC_PLAYER_CURRENTLY_HAS_NO_CITIES', 'Amount', '1');
INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
VALUES ('DEFAULT_DEFEAT_REQUIREMENTS', 'EC_PLAYER_CURRENTLY_HAS_NO_CITIES');
