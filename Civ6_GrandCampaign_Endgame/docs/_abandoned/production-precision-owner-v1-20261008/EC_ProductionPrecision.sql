-- Opt-in native restoration prototype. No modifier exists in a city until
-- gameplay explicitly creates this internal building; removing it removes
-- the modifier. Never use it for ordinary production or across a turn.
INSERT OR IGNORE INTO Types(Type,Kind)
VALUES ('BUILDING_EC_RESTORE_UNIT_MINUS_50','KIND_BUILDING');
INSERT OR IGNORE INTO Buildings
    (BuildingType,Name,Cost,PrereqDistrict,InternalOnly,MustPurchase)
VALUES ('BUILDING_EC_RESTORE_UNIT_MINUS_50','LOC_EC_ARCHIVE_STATUS',1,
    'DISTRICT_CITY_CENTER',1,1);
INSERT OR IGNORE INTO Modifiers(ModifierId,ModifierType)
VALUES ('EC_RESTORE_UNIT_MINUS_50','MODIFIER_SINGLE_CITY_ADJUST_UNIT_PRODUCTION_MODIFIER');
INSERT OR IGNORE INTO ModifierArguments(ModifierId,Name,Value)
VALUES ('EC_RESTORE_UNIT_MINUS_50','Amount','-50');
INSERT OR IGNORE INTO BuildingModifiers(BuildingType,ModifierId)
VALUES ('BUILDING_EC_RESTORE_UNIT_MINUS_50','EC_RESTORE_UNIT_MINUS_50');
