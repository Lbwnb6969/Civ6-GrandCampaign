-- Opt-in awakening actions: team victories require no member to hold the
-- temporary pre-showdown marker. No map placement, yield, trade, technology,
-- civic or scoring data is changed by this non-generating bonus resource.
INSERT OR IGNORE INTO Types(Type,Kind) VALUES('RESOURCE_EC_VICTORY_LOCK','KIND_RESOURCE');
INSERT OR IGNORE INTO Resources(ResourceType,Name,ResourceClassType,Frequency,SeaFrequency)
VALUES('RESOURCE_EC_VICTORY_LOCK','LOC_EC_VICTORY_LOCK','RESOURCECLASS_BONUS',0,0);
INSERT OR IGNORE INTO Requirements(RequirementId,RequirementType)
VALUES('EC_PLAYER_VICTORY_LOCKED','REQUIREMENT_PLAYER_HAS_RESOURCE_OWNED'),
('EC_TEAM_NO_VICTORY_LOCK','REQUIREMENT_COLLECTION_COUNT_EQUALS');
INSERT OR IGNORE INTO RequirementSets(RequirementSetId,RequirementSetType)
VALUES('EC_VICTORY_LOCKED_PLAYER','REQUIREMENTSET_TEST_ALL');
INSERT OR IGNORE INTO RequirementSetRequirements(RequirementSetId,RequirementId)
VALUES('EC_VICTORY_LOCKED_PLAYER','EC_PLAYER_VICTORY_LOCKED');
INSERT OR IGNORE INTO RequirementArguments(RequirementId,Name,Value)
VALUES('EC_PLAYER_VICTORY_LOCKED','ResourceType','RESOURCE_EC_VICTORY_LOCK'),
('EC_TEAM_NO_VICTORY_LOCK','CollectionType','COLLECTION_TEAM_PLAYERS'),
('EC_TEAM_NO_VICTORY_LOCK','RequirementSetId','EC_VICTORY_LOCKED_PLAYER'),
('EC_TEAM_NO_VICTORY_LOCK','Count','0');
INSERT OR IGNORE INTO RequirementSetRequirements(RequirementSetId,RequirementId)
SELECT RequirementSetId,'EC_TEAM_NO_VICTORY_LOCK' FROM Victories WHERE RequirementSetId IS NOT NULL;
