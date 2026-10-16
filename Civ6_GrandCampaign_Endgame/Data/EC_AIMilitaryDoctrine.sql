-- AI military doctrine slice. Loaded only when EC_AI_MILITARY_PRODUCTION_TEST=1.
-- This changes existing native AI preference/operation rows; it never creates units.

-- Pre-war preparation: make military specialization and production a stronger
-- default while leaving food, gold, science and maintenance systems intact.
UPDATE AiFavoredItems
SET Value = 30
WHERE ListType = 'DefaultYieldBias'
  AND Item = 'YIELD_PRODUCTION';

UPDATE AiFavoredItems
SET Value = 2
WHERE ListType = 'DefaultCitySpecialization'
  AND Item = 'BUILD_MILITARY_UNITS';

-- Native military-victory strategy: increase standing-army and military
-- production preferences when that strategy is active.
UPDATE AiFavoredItems
SET Value = 30
WHERE ListType = 'MilitaryVictoryYields'
  AND Item = 'YIELD_PRODUCTION';

UPDATE AiFavoredItems
SET Value = 30
WHERE ListType = 'MilitaryVictoryPseudoYields'
  AND Item IN (
    'PSEUDOYIELD_UNIT_COMBAT',
    'PSEUDOYIELD_UNIT_NAVAL_COMBAT',
    'PSEUDOYIELD_UNIT_AIR_COMBAT'
  );

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('MilitaryVictoryPseudoYields', 'PSEUDOYIELD_STANDING_ARMY_NUMBER', 8),
  ('MilitaryVictoryPseudoYields', 'PSEUDOYIELD_STANDING_ARMY_VALUE', 5);

UPDATE AiFavoredItems
SET Value = 3
WHERE ListType = 'MilitaryVictoryOperations'
  AND Item = 'CITY_ASSAULT';

-- War-time mobilization: allow an additional assault and defensive operation
-- while keeping the native operation types and per-war list semantics. RHAI's
-- mature Ops slice raises the base city-assault cap to three; keep defense at
-- two and apply the higher assault cap to pre-war/military-victory planning.
UPDATE AiFavoredItems
SET Value = 3
WHERE ListType = 'BaseOperationsLimits'
  AND Item = 'CITY_ASSAULT';

UPDATE AiFavoredItems
SET Value = 2
WHERE ListType = 'BaseOperationsLimits'
  AND Item = 'OP_DEFENSE';

UPDATE AiFavoredItems
SET Value = 2
WHERE ListType = 'PerWarOperationsLimits'
  AND Item = 'CITY_ASSAULT';

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES ('PerWarOperationsLimits', 'OP_DEFENSE', 1);

-- The native Naval Superiority limit is intentionally dormant until a strategy
-- raises the operation type. Mirror RHAI's bounded naval strategy hook: allow
-- one additional superiority operation per war while keeping the native base
-- limit and the R61 wartime definition intact.
INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES ('PerWarOperationsLimits', 'NAVAL_SUPERIORITY', 1);

-- Make native wartime city operations compete earlier once a war exists.
UPDATE AiOperationDefs
SET Priority = 4
WHERE OperationName IN ('Wartime Attack Enemy City', 'Wartime Attack Walled City');

-- RHAI's mature Ops2 slice lets an already-at-war AI form both native city
-- attack definitions at a lower success threshold while retaining a bounded
-- unit floor. Combined with the existing team requirements below, this keeps
-- the planner committed to replenishable assaults instead of waiting for an
-- oversized strength advantage.
UPDATE AiOperationDefs
SET MinOddsOfSuccess = 0.2,
    MustHaveUnits = 4
WHERE OperationName = 'Wartime Attack Enemy City';

UPDATE AiOperationDefs
SET MinOddsOfSuccess = 0.2,
    MustHaveUnits = 5
WHERE OperationName = 'Wartime Attack Walled City';

-- RHAI's wartime operation slice lowers the native strength threshold for
-- forming both land assault teams. This lets a fighting AI start an existing
-- attack with a bounded, replenishable force instead of waiting for an
-- oversized advantage; it does not declare wars or add an operation.
UPDATE AiOperationTeams
SET InitialStrengthAdvantage = -1,
    OngoingStrengthAdvantage = 0.5
WHERE TeamName = 'Simple City Attack Force'
  AND OperationName = 'Wartime Attack Enemy City';

UPDATE AiOperationTeams
SET InitialStrengthAdvantage = -10,
    OngoingStrengthAdvantage = -0.5
WHERE TeamName = 'City Attack Force'
  AND OperationName = 'Wartime Attack Walled City';

-- Coastal wartime attacks use the native City Naval Attack Force. Reuse the
-- mature RHAI thresholds for both coastal assault variants so a fleet can
-- form and replenish earlier without adding a custom operation team.
UPDATE AiOperationTeams
SET InitialStrengthAdvantage = -10,
    OngoingStrengthAdvantage = 0.1
WHERE TeamName = 'City Naval Attack Force'
  AND OperationName = 'Wartime Attack Enemy City';

UPDATE AiOperationTeams
SET InitialStrengthAdvantage = -10,
    OngoingStrengthAdvantage = 0.2
WHERE TeamName = 'City Naval Attack Force'
  AND OperationName = 'Wartime Attack Walled City';

-- The native City Defense row does not declare its operation type in this
-- Steam build. Make the existing defensive action explicit and let it form
-- with a small garrison, so the strategy-level OP_DEFENSE preference reaches
-- the operation definition without inventing a new operation.
UPDATE AiOperationDefs
SET OperationType = 'OP_DEFENSE',
    MustHaveUnits = 2
WHERE OperationName = 'City Defense';

-- RHAI's mature City Defense slice also raises the native team requirement:
-- a defensive operation should gather a small combat core and at least one
-- ranged unit before it is considered ready. Keep the cap bounded and use
-- the existing native team; this creates unit demand through the operation
-- planner without directly spawning units or changing human defenses.
UPDATE OpTeamRequirements
SET MinNumber = 2,
    MaxNumber = 8
WHERE TeamName = 'City Defense'
  AND AiType = 'UNITAI_COMBAT';

INSERT OR IGNORE INTO OpTeamRequirements
  (TeamName, AiType, MinNumber, MaxNumber)
VALUES
  ('City Defense', 'UNITTYPE_RANGED', 1, 7);

-- For walled-city assaults, RHAI's mature operation slice asks the native
-- City Attack Force to carry a larger melee core and a real siege package.
-- These requirements apply to an existing wartime operation team, so the AI
-- must produce the units through its normal queues before the assault forms.
UPDATE OpTeamRequirements
SET MinNumber = 3,
    MaxNumber = 8
WHERE TeamName = 'City Attack Force'
  AND AiType = 'UNITTYPE_MELEE';

UPDATE OpTeamRequirements
SET MinNumber = 3,
    MaxNumber = 5
WHERE TeamName = 'City Attack Force'
  AND AiType = 'UNITTYPE_SIEGE';

UPDATE OpTeamRequirements
SET MinNumber = 2,
    MaxNumber = 6
WHERE TeamName = 'City Attack Force'
  AND AiType = 'UNITTYPE_SIEGE_ALL';

-- RHAI's naval force slice gives coastal wars a real combat core and a
-- bounded fleet floor. Keep the existing native team and only add/update
-- rows that already have native AiType identifiers.
INSERT OR IGNORE INTO OpTeamRequirements
  (TeamName, AiType, MinNumber, MaxNumber)
VALUES
  ('City Naval Attack Force', 'UNITAI_COMBAT', 6, 14);

UPDATE OpTeamRequirements
SET MinNumber = 3,
    MaxNumber = 12,
    MinPercentage = 0.6,
    MaxPercentage = 1
WHERE TeamName = 'City Naval Attack Force'
  AND AiType = 'UNITTYPE_NAVAL';

UPDATE OpTeamRequirements
SET MinNumber = 2,
    MaxNumber = 7
WHERE TeamName = 'City Naval Attack Force'
  AND AiType = 'UNITTYPE_MELEE';

UPDATE OpTeamRequirements
SET MinNumber = 0,
    MaxNumber = 7
WHERE TeamName = 'City Naval Attack Force'
  AND AiType = 'UNITTYPE_RANGED';

-- Coastal city defense is a separate native team from coastal city attack.
-- RHAI's mature Ops4 slice gives it a real combat core and a bounded fleet
-- floor so threatened coastal cities also create normal naval reinforcement
-- demand. Use only AiTypes present in the Steam build.
UPDATE AiOperationTeams
SET InitialStrengthAdvantage = -7
WHERE TeamName = 'City Naval Defense'
  AND OperationName = 'City Defense';

UPDATE OpTeamRequirements
SET MinNumber = 2,
    MaxNumber = 8,
    MinPercentage = 0.6,
    MaxPercentage = 1
WHERE TeamName = 'City Naval Defense'
  AND AiType = 'UNITTYPE_NAVAL';

UPDATE OpTeamRequirements
SET MinNumber = 0,
    MaxNumber = 3,
    MinPercentage = 0,
    MaxPercentage = 0.5
WHERE TeamName = 'City Naval Defense'
  AND AiType = 'UNITTYPE_MELEE';

INSERT OR IGNORE INTO OpTeamRequirements
  (TeamName, AiType, MinNumber, MaxNumber)
VALUES
  ('City Naval Defense', 'UNITAI_COMBAT', 2, 10);

-- RHAI's Naval Superiority slice is explicitly a wartime operation. Give the
-- existing native team a bounded fleet, melee escort and ranged support floor
-- so this operation creates normal production demand only after war begins.
UPDATE AiOperationTeams
SET InitialStrengthAdvantage = -2,
    OngoingStrengthAdvantage = 0.6
WHERE TeamName = 'Naval Superiority Force'
  AND OperationName = 'Naval Superiority';

UPDATE OpTeamRequirements
SET MinNumber = 3,
    MaxNumber = 9
WHERE TeamName = 'Naval Superiority Force'
  AND AiType = 'UNITTYPE_NAVAL';

UPDATE OpTeamRequirements
SET MinNumber = 1,
    MaxNumber = 5
WHERE TeamName = 'Naval Superiority Force'
  AND AiType = 'UNITTYPE_MELEE';

UPDATE OpTeamRequirements
SET MinNumber = 1,
    MaxNumber = 6
WHERE TeamName = 'Naval Superiority Force'
  AND AiType = 'UNITTYPE_RANGED';

UPDATE AiOperationDefs
SET MinOddsOfSuccess = 0.25,
    MustHaveUnits = 3,
    EnemyType = 'WAR'
WHERE OperationName = 'Naval Superiority';

-- RHAI and the native trigger table use this same upgrade behavior tree.
-- Raising its priority improves replacement/reinforcement timing after a
-- technology or civic upgrade without touching the human player.
UPDATE TriggeredBehaviorTrees
SET Priority = 4
WHERE TriggerType IN ('TRIGGER_TECH_UPGRADE', 'TRIGGER_CIVIC_UPGRADE')
  AND TreeName = 'Upgrade Units';

-- Pre-war and wartime unit composition. RHAI uses the native
-- UnitPromotionClasses system to keep a standing army supplied with a
-- balanced frontline, ranged, siege and support mix. The values are bounded
-- preference weights, not direct unit creation or a production multiplier.
INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES ('EC_AI_MILITARY_UNIT_BUILDS');

INSERT OR IGNORE INTO AiLists (ListType, LeaderType, System)
VALUES ('EC_AI_MILITARY_UNIT_BUILDS', 'TRAIT_LEADER_MAJOR_CIV', 'UnitPromotionClasses');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Favored, Value)
VALUES
  ('EC_AI_MILITARY_UNIT_BUILDS', 'PROMOTION_CLASS_MELEE', 1, 5),
  ('EC_AI_MILITARY_UNIT_BUILDS', 'PROMOTION_CLASS_RANGED', 1, 5),
  ('EC_AI_MILITARY_UNIT_BUILDS', 'PROMOTION_CLASS_SIEGE', 1, 6),
  ('EC_AI_MILITARY_UNIT_BUILDS', 'PROMOTION_CLASS_ANTI_CAVALRY', 1, 2),
  ('EC_AI_MILITARY_UNIT_BUILDS', 'PROMOTION_CLASS_HEAVY_CAVALRY', 1, 3),
  ('EC_AI_MILITARY_UNIT_BUILDS', 'PROMOTION_CLASS_SUPPORT', 1, 2),
  ('EC_AI_MILITARY_UNIT_BUILDS', 'PROMOTION_CLASS_NAVAL_RANGED', 1, 3),
  ('EC_AI_MILITARY_UNIT_BUILDS', 'PROMOTION_CLASS_AIR_BOMBER', 1, 3);

-- Supported-unit capacity. The native modifier is city-scoped; a small AI
-- baseline and a second known-opponent wartime layer let the AI sustain the
-- additional production without changing the human player's supply rules.
-- High-difficulty AI receives one further bounded slot per city, paired with
-- its existing high-difficulty military-production gate.
INSERT OR IGNORE INTO Modifiers (ModifierId, ModifierType, SubjectRequirementSetId)
VALUES
  ('EC_AI_MILITARY_SUPPORT_BASE', 'MODIFIER_PLAYER_CITIES_ADJUST_NUM_UNITS_SUPPORTED', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_SUPPORT_WARTIME', 'MODIFIER_PLAYER_CITIES_ADJUST_NUM_UNITS_SUPPORTED', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_SUPPORT_HIGH_DIFFICULTY', 'MODIFIER_PLAYER_CITIES_ADJUST_NUM_UNITS_SUPPORTED', 'PLAYER_IS_HIGH_DIFFICULTY_AI');

INSERT OR IGNORE INTO ModifierArguments (ModifierId, Name, Value)
VALUES
  ('EC_AI_MILITARY_SUPPORT_BASE', 'Amount', 1),
  ('EC_AI_MILITARY_SUPPORT_WARTIME', 'Amount', 1),
  ('EC_AI_MILITARY_SUPPORT_HIGH_DIFFICULTY', 'Amount', 1);

INSERT OR IGNORE INTO TraitModifiers (TraitType, ModifierId)
VALUES
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_SUPPORT_BASE'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_SUPPORT_WARTIME'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_SUPPORT_HIGH_DIFFICULTY');

-- Active-war strategy lists. RHAI separates these from the default lists so
-- the native STRATEGY_AT_WAR hook can raise production, standing-army desire,
-- unit composition and military city specialization only while a war is active.
INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES
  ('EC_AI_MILITARY_AT_WAR_YIELDS'),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS'),
  ('EC_AI_MILITARY_AT_WAR_UNIT_BUILDS'),
  ('EC_AI_MILITARY_AT_WAR_SPECIALISE'),
  ('EC_AI_MILITARY_AT_WAR_BUILDINGS'),
  ('EC_AI_MILITARY_AT_WAR_DISTRICTS'),
  ('EC_AI_MILITARY_AT_WAR_SAVINGS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES
  ('EC_AI_MILITARY_AT_WAR_YIELDS', 'Yields'),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS', 'PseudoYields'),
  ('EC_AI_MILITARY_AT_WAR_UNIT_BUILDS', 'UnitPromotionClasses'),
  ('EC_AI_MILITARY_AT_WAR_SPECIALISE', 'AiBuildSpecializations'),
  ('EC_AI_MILITARY_AT_WAR_BUILDINGS', 'Buildings'),
  ('EC_AI_MILITARY_AT_WAR_DISTRICTS', 'Districts'),
  ('EC_AI_MILITARY_AT_WAR_SAVINGS', 'SavingTypes');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_YIELDS'),
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_PSEUDOS'),
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_UNIT_BUILDS'),
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_SPECIALISE'),
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_BUILDINGS'),
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_DISTRICTS'),
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_SAVINGS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_AT_WAR_YIELDS', 'YIELD_PRODUCTION', 25),
  -- Active wars need cash for the R78 native unit-purchase discount path.
  ('EC_AI_MILITARY_AT_WAR_YIELDS', 'YIELD_GOLD', 15),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS', 'PSEUDOYIELD_UNIT_COMBAT', 8),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS', 'PSEUDOYIELD_UNIT_NAVAL_COMBAT', 8),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS', 'PSEUDOYIELD_UNIT_AIR_COMBAT', 10),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_NUMBER', 12),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS', 'PSEUDOYIELD_GPP_GENERAL', 50),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_VALUE', 8),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENSES', 10),
  ('EC_AI_MILITARY_AT_WAR_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENDING_UNITS', 8),
  ('EC_AI_MILITARY_AT_WAR_UNIT_BUILDS', 'PROMOTION_CLASS_MELEE', 2),
  ('EC_AI_MILITARY_AT_WAR_UNIT_BUILDS', 'PROMOTION_CLASS_RANGED', 2),
  ('EC_AI_MILITARY_AT_WAR_UNIT_BUILDS', 'PROMOTION_CLASS_SIEGE', 3),
  ('EC_AI_MILITARY_AT_WAR_UNIT_BUILDS', 'PROMOTION_CLASS_HEAVY_CAVALRY', 2),
  ('EC_AI_MILITARY_AT_WAR_UNIT_BUILDS', 'PROMOTION_CLASS_SUPPORT', 1),
  ('EC_AI_MILITARY_AT_WAR_UNIT_BUILDS', 'PROMOTION_CLASS_NAVAL_RANGED', 2),
  ('EC_AI_MILITARY_AT_WAR_UNIT_BUILDS', 'PROMOTION_CLASS_AIR_BOMBER', 2),
  ('EC_AI_MILITARY_AT_WAR_SPECIALISE', 'BUILD_MILITARY_UNITS', 3),
  ('EC_AI_MILITARY_AT_WAR_SPECIALISE', 'BUILD_CITY_DEFENSES', 2),
  ('EC_AI_MILITARY_AT_WAR_BUILDINGS', 'BUILDING_BARRACKS', 2),
  ('EC_AI_MILITARY_AT_WAR_BUILDINGS', 'BUILDING_STABLE', 2),
  ('EC_AI_MILITARY_AT_WAR_BUILDINGS', 'BUILDING_ARMORY', 2),
  ('EC_AI_MILITARY_AT_WAR_BUILDINGS', 'BUILDING_MILITARY_ACADEMY', 2),
  ('EC_AI_MILITARY_AT_WAR_DISTRICTS', 'DISTRICT_ENCAMPMENT', 4),
  ('EC_AI_MILITARY_AT_WAR_DISTRICTS', 'DISTRICT_AERODROME', 2),
  -- R77: match RHAI's aggressive spending direction so active wars spend
  -- reserved gold on units instead of holding it for later purchases.
  ('EC_AI_MILITARY_AT_WAR_SAVINGS', 'SAVING_UNITS', -2);

-- Strategy-scoped operation types. RHAI separates AiOperationTypes from
-- PerWarOperationTypes so a strong or active-war strategy can commit to more
-- assault/defense work without inventing new operations or war declarations.
INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES
  ('EC_AI_MILITARY_AT_WAR_OPERATIONS'),
  ('EC_AI_MILITARY_AT_WAR_PER_WAR_OPERATIONS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES
  ('EC_AI_MILITARY_AT_WAR_OPERATIONS', 'AiOperationTypes'),
  ('EC_AI_MILITARY_AT_WAR_PER_WAR_OPERATIONS', 'PerWarOperationTypes');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_OPERATIONS'),
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_PER_WAR_OPERATIONS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_AT_WAR_OPERATIONS', 'CITY_ASSAULT', 1),
  ('EC_AI_MILITARY_AT_WAR_OPERATIONS', 'OP_DEFENSE', 1),
  ('EC_AI_MILITARY_AT_WAR_OPERATIONS', 'NAVAL_SUPERIORITY', 1),
  ('EC_AI_MILITARY_AT_WAR_PER_WAR_OPERATIONS', 'CITY_ASSAULT', 1),
  ('EC_AI_MILITARY_AT_WAR_PER_WAR_OPERATIONS', 'OP_DEFENSE', 1),
  ('EC_AI_MILITARY_AT_WAR_PER_WAR_OPERATIONS', 'NAVAL_SUPERIORITY', 1);

-- War-time technology path. RHAI and the native victory/leader data use the
-- Technologies list system for strategic research preferences; keep this
-- list bounded so the AI still evaluates economy and victory technologies.
INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES ('EC_AI_MILITARY_AT_WAR_TECHS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES ('EC_AI_MILITARY_AT_WAR_TECHS', 'Technologies');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_TECHS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_MILITARY_ENGINEERING', 5),
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_METAL_CASTING', 5),
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_MILITARY_SCIENCE', 5),
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_COMBUSTION', 5),
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_COMBINED_ARMS', 6),
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_ADVANCED_FLIGHT', 5),
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_STEALTH_TECHNOLOGY', 5),
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_NUCLEAR_FISSION', 5),
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_NUCLEAR_FUSION', 5),
  ('EC_AI_MILITARY_AT_WAR_TECHS', 'TECH_ROBOTICS', 5);

-- War-time civic path. Keep policy priorities scoped to the native
-- STRATEGY_AT_WAR hook so military civics compete more strongly only while
-- the AI is actually fighting; civic costs and prerequisites remain native.
INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES ('EC_AI_MILITARY_AT_WAR_CIVICS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES ('EC_AI_MILITARY_AT_WAR_CIVICS', 'Civics');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_CIVICS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_AT_WAR_CIVICS', 'CIVIC_MILITARY_TRADITION', 5),
  ('EC_AI_MILITARY_AT_WAR_CIVICS', 'CIVIC_MILITARY_TRAINING', 5),
  ('EC_AI_MILITARY_AT_WAR_CIVICS', 'CIVIC_DEFENSIVE_TACTICS', 5),
  ('EC_AI_MILITARY_AT_WAR_CIVICS', 'CIVIC_MERCENARIES', 5),
  ('EC_AI_MILITARY_AT_WAR_CIVICS', 'CIVIC_NATIONALISM', 5),
  ('EC_AI_MILITARY_AT_WAR_CIVICS', 'CIVIC_SCORCHED_EARTH', 4),
  ('EC_AI_MILITARY_AT_WAR_CIVICS', 'CIVIC_MOBILIZATION', 6),
  ('EC_AI_MILITARY_AT_WAR_CIVICS', 'CIVIC_RAPID_DEPLOYMENT', 6);

-- War commitment: BAIT's public design and RHAI's mature diplomacy list both
-- resist cheap peace while an AI is already fighting. Keep this preference
-- scoped to STRATEGY_AT_WAR and use small negative values so diplomacy can
-- still end a clearly losing war; this does not declare wars or block peace.
INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES ('EC_AI_MILITARY_AT_WAR_DIPLOMACY');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES ('EC_AI_MILITARY_AT_WAR_DIPLOMACY', 'DiplomaticActions');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_AT_WAR_DIPLOMACY');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Favored, Value)
VALUES
  ('EC_AI_MILITARY_AT_WAR_DIPLOMACY', 'DIPLOACTION_MAKE_PEACE', 0, -25),
  ('EC_AI_MILITARY_AT_WAR_DIPLOMACY', 'DIPLOACTION_PROPOSE_PEACE_DEAL', 0, -50);

-- Resource-positioning layer: Real Strategy and RHAI both use the native
-- PlotEvaluations system to make strategic-resource plots more attractive.
-- Reuse one bounded list for war, pre-war strength and military recovery so
-- normal expansion can secure the resources needed for replenishment and
-- upgrades before the queue is under pressure.
INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES ('EC_AI_MILITARY_RESOURCE_SETTLEMENT');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES ('EC_AI_MILITARY_RESOURCE_SETTLEMENT', 'PlotEvaluations');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES
  ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_RESOURCE_SETTLEMENT'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_RESOURCE_SETTLEMENT'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_RESOURCE_SETTLEMENT');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value, StringVal)
VALUES
  ('EC_AI_MILITARY_RESOURCE_SETTLEMENT', 'Resource Class', 4, 'RESOURCECLASS_STRATEGIC'),
  ('EC_AI_MILITARY_RESOURCE_SETTLEMENT', 'Specific Resource', 3, 'RESOURCE_HORSES'),
  ('EC_AI_MILITARY_RESOURCE_SETTLEMENT', 'Specific Resource', 4, 'RESOURCE_IRON'),
  ('EC_AI_MILITARY_RESOURCE_SETTLEMENT', 'Specific Resource', 4, 'RESOURCE_NITER'),
  ('EC_AI_MILITARY_RESOURCE_SETTLEMENT', 'Specific Resource', 4, 'RESOURCE_COAL'),
  ('EC_AI_MILITARY_RESOURCE_SETTLEMENT', 'Specific Resource', 5, 'RESOURCE_OIL'),
  ('EC_AI_MILITARY_RESOURCE_SETTLEMENT', 'Specific Resource', 6, 'RESOURCE_ALUMINUM'),
  ('EC_AI_MILITARY_RESOURCE_SETTLEMENT', 'Specific Resource', 8, 'RESOURCE_URANIUM');

-- Conditional pre-war preparation. The mature RHAI strategy uses native
-- strength/technology/score conditions; this path does not add automatic war
-- declarations or diplomatic actions to the pre-war strategy.
INSERT OR IGNORE INTO Strategies (StrategyType, NumConditionsNeeded)
VALUES ('STRATEGY_STRENGTH_ADV', 2);

INSERT OR IGNORE INTO StrategyConditions
  (StrategyType, ConditionFunction, ThresholdValue, Disqualifier)
VALUES
  ('STRATEGY_STRENGTH_ADV', 'Leads Military', 25, 0),
  ('STRATEGY_STRENGTH_ADV', 'Has Tech Lead', 30, 0),
  ('STRATEGY_STRENGTH_ADV', 'Leads Score', 20, 0),
  ('STRATEGY_STRENGTH_ADV', 'Is Not Major', 0, 1);

INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES
  ('EC_AI_MILITARY_STRENGTH_YIELDS'),
  ('EC_AI_MILITARY_STRENGTH_PSEUDOS'),
  ('EC_AI_MILITARY_STRENGTH_UNIT_BUILDS'),
  ('EC_AI_MILITARY_STRENGTH_SPECIALISE'),
  ('EC_AI_MILITARY_STRENGTH_BUILDINGS'),
  ('EC_AI_MILITARY_STRENGTH_DISTRICTS'),
  ('EC_AI_MILITARY_STRENGTH_TECHS'),
  ('EC_AI_MILITARY_STRENGTH_CIVICS'),
  ('EC_AI_MILITARY_STRENGTH_SAVINGS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES
  ('EC_AI_MILITARY_STRENGTH_YIELDS', 'Yields'),
  ('EC_AI_MILITARY_STRENGTH_PSEUDOS', 'PseudoYields'),
  ('EC_AI_MILITARY_STRENGTH_UNIT_BUILDS', 'UnitPromotionClasses'),
  ('EC_AI_MILITARY_STRENGTH_SPECIALISE', 'AiBuildSpecializations'),
  ('EC_AI_MILITARY_STRENGTH_BUILDINGS', 'Buildings'),
  ('EC_AI_MILITARY_STRENGTH_DISTRICTS', 'Districts'),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'Technologies'),
  ('EC_AI_MILITARY_STRENGTH_CIVICS', 'Civics'),
  ('EC_AI_MILITARY_STRENGTH_SAVINGS', 'SavingTypes');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_YIELDS'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_PSEUDOS'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_UNIT_BUILDS'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_SPECIALISE'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_BUILDINGS'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_DISTRICTS'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_TECHS'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_CIVICS'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_SAVINGS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  -- Raise the pre-war production preference without adding another city
  -- production modifier; wartime and under-attack layers remain stronger.
  ('EC_AI_MILITARY_STRENGTH_YIELDS', 'YIELD_PRODUCTION', 24),
  -- RHAI's aggressive strategy also values native gold; keep a smaller
  -- pre-war amount so purchase funding improves without replacing production.
  ('EC_AI_MILITARY_STRENGTH_YIELDS', 'YIELD_GOLD', 6),
  -- R77: RHAI's default unit-saving baseline is 3; use it for the
  -- pre-war strength layer so preparation also funds earlier replenishment.
  ('EC_AI_MILITARY_STRENGTH_SAVINGS', 'SAVING_UNITS', 3),
  ('EC_AI_MILITARY_STRENGTH_PSEUDOS', 'PSEUDOYIELD_UNIT_COMBAT', 5),
  -- RHAI's STRATEGY_STRENGTH_ADV values make a strong pre-war AI value
  -- naval and air formations more heavily; keep these as bounded native
  -- pseudo-yield preferences rather than direct unit creation.
  ('EC_AI_MILITARY_STRENGTH_PSEUDOS', 'PSEUDOYIELD_UNIT_NAVAL_COMBAT', 30),
  ('EC_AI_MILITARY_STRENGTH_PSEUDOS', 'PSEUDOYIELD_UNIT_AIR_COMBAT', 20),
  ('EC_AI_MILITARY_STRENGTH_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_NUMBER', 10),
  ('EC_AI_MILITARY_STRENGTH_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_VALUE', 6),
  ('EC_AI_MILITARY_STRENGTH_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENSES', 6),
  ('EC_AI_MILITARY_STRENGTH_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENDING_UNITS', 4),
  ('EC_AI_MILITARY_STRENGTH_UNIT_BUILDS', 'PROMOTION_CLASS_MELEE', 2),
  ('EC_AI_MILITARY_STRENGTH_UNIT_BUILDS', 'PROMOTION_CLASS_RANGED', 2),
  -- RHAI Military_Strat.xml uses 11 siege and 45 bomber preference for
  -- a strong pre-war AI; keep this bounded to STRATEGY_STRENGTH_ADV.
  ('EC_AI_MILITARY_STRENGTH_UNIT_BUILDS', 'PROMOTION_CLASS_SIEGE', 11),
  ('EC_AI_MILITARY_STRENGTH_UNIT_BUILDS', 'PROMOTION_CLASS_HEAVY_CAVALRY', 2),
  ('EC_AI_MILITARY_STRENGTH_UNIT_BUILDS', 'PROMOTION_CLASS_SUPPORT', 1),
  ('EC_AI_MILITARY_STRENGTH_UNIT_BUILDS', 'PROMOTION_CLASS_NAVAL_RANGED', 2),
  ('EC_AI_MILITARY_STRENGTH_UNIT_BUILDS', 'PROMOTION_CLASS_AIR_BOMBER', 45),
  ('EC_AI_MILITARY_STRENGTH_SPECIALISE', 'BUILD_MILITARY_UNITS', 2),
  ('EC_AI_MILITARY_STRENGTH_SPECIALISE', 'BUILD_CITY_DEFENSES', 2),
  ('EC_AI_MILITARY_STRENGTH_BUILDINGS', 'BUILDING_BARRACKS', 1),
  ('EC_AI_MILITARY_STRENGTH_BUILDINGS', 'BUILDING_STABLE', 1),
  ('EC_AI_MILITARY_STRENGTH_BUILDINGS', 'BUILDING_ARMORY', 1),
  ('EC_AI_MILITARY_STRENGTH_BUILDINGS', 'BUILDING_MILITARY_ACADEMY', 1),
  ('EC_AI_MILITARY_STRENGTH_DISTRICTS', 'DISTRICT_ENCAMPMENT', 3),
  ('EC_AI_MILITARY_STRENGTH_DISTRICTS', 'DISTRICT_AERODROME', 1);

UPDATE AiFavoredItems
SET Favored = 1
WHERE ListType = 'EC_AI_MILITARY_STRENGTH_UNIT_BUILDS'
  AND Item = 'PROMOTION_CLASS_AIR_BOMBER';

-- Pre-war technology path. A strong AI should prepare its military research
-- before a war starts; keep these values below the active-war layer while
-- reusing only native technology identifiers already checked in Technologies.xml.
INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_MILITARY_ENGINEERING', 3),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_METAL_CASTING', 3),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_MILITARY_SCIENCE', 4),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_COMBUSTION', 4),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_COMBINED_ARMS', 4),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_ADVANCED_FLIGHT', 3),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_STEALTH_TECHNOLOGY', 3),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_NUCLEAR_FISSION', 3),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_NUCLEAR_FUSION', 3),
  ('EC_AI_MILITARY_STRENGTH_TECHS', 'TECH_ROBOTICS', 3);

-- Pre-war civic path. Keep this below the active-war civic weights so a
-- strong AI prepares its policy tree without making military civics a global
-- priority during ordinary peaceful turns.
INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_STRENGTH_CIVICS', 'CIVIC_MILITARY_TRADITION', 3),
  ('EC_AI_MILITARY_STRENGTH_CIVICS', 'CIVIC_MILITARY_TRAINING', 3),
  ('EC_AI_MILITARY_STRENGTH_CIVICS', 'CIVIC_DEFENSIVE_TACTICS', 3),
  ('EC_AI_MILITARY_STRENGTH_CIVICS', 'CIVIC_MERCENARIES', 3),
  ('EC_AI_MILITARY_STRENGTH_CIVICS', 'CIVIC_NATIONALISM', 3),
  ('EC_AI_MILITARY_STRENGTH_CIVICS', 'CIVIC_SCORCHED_EARTH', 2),
  ('EC_AI_MILITARY_STRENGTH_CIVICS', 'CIVIC_MOBILIZATION', 4),
  ('EC_AI_MILITARY_STRENGTH_CIVICS', 'CIVIC_RAPID_DEPLOYMENT', 4);

-- Strong pre-war civilizations may prepare assault and defense operation
-- capacity, but the values remain small and use only native operation types.
INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES
  ('EC_AI_MILITARY_STRENGTH_CITY_EVENTS'),
  ('EC_AI_MILITARY_STRENGTH_OPERATIONS'),
  ('EC_AI_MILITARY_STRENGTH_PER_WAR_OPERATIONS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES
  ('EC_AI_MILITARY_STRENGTH_CITY_EVENTS', 'CityEvents'),
  ('EC_AI_MILITARY_STRENGTH_OPERATIONS', 'AiOperationTypes'),
  ('EC_AI_MILITARY_STRENGTH_PER_WAR_OPERATIONS', 'PerWarOperationTypes');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_CITY_EVENTS'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_OPERATIONS'),
  ('STRATEGY_STRENGTH_ADV', 'EC_AI_MILITARY_STRENGTH_PER_WAR_OPERATIONS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, StringVal)
VALUES
  ('EC_AI_MILITARY_STRENGTH_CITY_EVENTS', 'CITY_EVENT_DEFAULT', 'Upgrade Units'),
  ('EC_AI_MILITARY_STRENGTH_CITY_EVENTS', 'CITY_UNDER_THREAT', 'Upgrade Units');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_STRENGTH_OPERATIONS', 'CITY_ASSAULT', 1),
  ('EC_AI_MILITARY_STRENGTH_OPERATIONS', 'OP_DEFENSE', 1),
  ('EC_AI_MILITARY_STRENGTH_PER_WAR_OPERATIONS', 'CITY_ASSAULT', 1),
  ('EC_AI_MILITARY_STRENGTH_PER_WAR_OPERATIONS', 'OP_DEFENSE', 1);

-- War-time city-event strategy. RHAI's mature Ops slice uses the same native
-- CityEvents system and the engine-recognized STRATEGY_AT_WAR hook to make
-- threatened cities choose the Upgrade Units behavior tree. The strategy row
-- is supplied here because it is not present in the base data set; INSERT OR
-- IGNORE keeps a compatible definition from another AI overhaul intact.
INSERT OR IGNORE INTO Strategies (StrategyType, NumConditionsNeeded)
VALUES ('STRATEGY_AT_WAR', 0);

INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES ('EC_AI_MILITARY_WARTIME_CITY_EVENTS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES ('EC_AI_MILITARY_WARTIME_CITY_EVENTS', 'CityEvents');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES ('STRATEGY_AT_WAR', 'EC_AI_MILITARY_WARTIME_CITY_EVENTS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, StringVal)
VALUES
  ('EC_AI_MILITARY_WARTIME_CITY_EVENTS', 'CITY_EVENT_DEFAULT', 'Upgrade Units'),
  ('EC_AI_MILITARY_WARTIME_CITY_EVENTS', 'CITY_UNDER_THREAT', 'Upgrade Units');

-- Bounded military-economy support. The base discount applies only to AI;
-- the technology gate represents the medieval/renaissance transition and the
-- high-difficulty gate keeps the additional discount out of lower difficulties.
INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
VALUES ('EC_AI_MILITARY_TECH_GATE', 'REQUIREMENTSET_TEST_ALL');

INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
VALUES ('EC_AI_MILITARY_HAS_MILITARY_ENGINEERING', 'REQUIREMENT_PLAYER_HAS_TECHNOLOGY');

INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
VALUES ('EC_AI_MILITARY_HAS_MILITARY_ENGINEERING', 'TechnologyType', 'TECH_MILITARY_ENGINEERING');

INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
VALUES
  ('EC_AI_MILITARY_TECH_GATE', 'REQUIRES_PLAYER_IS_AI'),
  ('EC_AI_MILITARY_TECH_GATE', 'EC_AI_MILITARY_HAS_MILITARY_ENGINEERING');

-- Modernization gates for the city-scoped strategic-resource tier. Reuse the
-- native technology requirement type and keep each set AI-only.
INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
VALUES
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_INDUSTRIALIZATION', 'REQUIREMENTSET_TEST_ALL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_CHEMISTRY', 'REQUIREMENTSET_TEST_ALL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_NUCLEAR_FUSION', 'REQUIREMENTSET_TEST_ALL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_COMBINED_ARMS', 'REQUIREMENTSET_TEST_ALL');

INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
VALUES
  ('EC_AI_MILITARY_HAS_INDUSTRIALIZATION', 'REQUIREMENT_PLAYER_HAS_TECHNOLOGY'),
  ('EC_AI_MILITARY_HAS_CHEMISTRY', 'REQUIREMENT_PLAYER_HAS_TECHNOLOGY'),
  ('EC_AI_MILITARY_HAS_NUCLEAR_FUSION', 'REQUIREMENT_PLAYER_HAS_TECHNOLOGY'),
  ('EC_AI_MILITARY_HAS_COMBINED_ARMS', 'REQUIREMENT_PLAYER_HAS_TECHNOLOGY');

INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
VALUES
  ('EC_AI_MILITARY_HAS_INDUSTRIALIZATION', 'TechnologyType', 'TECH_INDUSTRIALIZATION'),
  ('EC_AI_MILITARY_HAS_CHEMISTRY', 'TechnologyType', 'TECH_CHEMISTRY'),
  ('EC_AI_MILITARY_HAS_NUCLEAR_FUSION', 'TechnologyType', 'TECH_NUCLEAR_FUSION'),
  ('EC_AI_MILITARY_HAS_COMBINED_ARMS', 'TechnologyType', 'TECH_COMBINED_ARMS');

INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
VALUES
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_INDUSTRIALIZATION', 'REQUIRES_PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_INDUSTRIALIZATION', 'EC_AI_MILITARY_HAS_INDUSTRIALIZATION'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_CHEMISTRY', 'REQUIRES_PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_CHEMISTRY', 'EC_AI_MILITARY_HAS_CHEMISTRY'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_NUCLEAR_FUSION', 'REQUIRES_PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_NUCLEAR_FUSION', 'EC_AI_MILITARY_HAS_NUCLEAR_FUSION'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_COMBINED_ARMS', 'REQUIRES_PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_COMBINED_ARMS', 'EC_AI_MILITARY_HAS_COMBINED_ARMS');

-- Strategic-resource relief: owning at least one native military strategic
-- resource reduces unit maintenance for AI only. The ANY set is deliberately
-- separate from the owner gate so a human player can never inherit it from
-- the shared major-civilization trait.
INSERT OR IGNORE INTO RequirementSets (RequirementSetId, RequirementSetType)
VALUES ('EC_AI_MILITARY_RESOURCE_ANY', 'REQUIREMENTSET_TEST_ANY');

INSERT OR IGNORE INTO Requirements (RequirementId, RequirementType)
VALUES
  ('EC_AI_MILITARY_HAS_IRON', 'REQUIREMENT_PLAYER_HAS_RESOURCE_OWNED'),
  ('EC_AI_MILITARY_HAS_HORSES', 'REQUIREMENT_PLAYER_HAS_RESOURCE_OWNED'),
  ('EC_AI_MILITARY_HAS_NITER', 'REQUIREMENT_PLAYER_HAS_RESOURCE_OWNED'),
  ('EC_AI_MILITARY_HAS_COAL', 'REQUIREMENT_PLAYER_HAS_RESOURCE_OWNED'),
  ('EC_AI_MILITARY_HAS_OIL', 'REQUIREMENT_PLAYER_HAS_RESOURCE_OWNED'),
  ('EC_AI_MILITARY_HAS_ALUMINUM', 'REQUIREMENT_PLAYER_HAS_RESOURCE_OWNED'),
  ('EC_AI_MILITARY_HAS_URANIUM', 'REQUIREMENT_PLAYER_HAS_RESOURCE_OWNED');

INSERT OR IGNORE INTO RequirementArguments (RequirementId, Name, Value)
VALUES
  ('EC_AI_MILITARY_HAS_IRON', 'ResourceType', 'RESOURCE_IRON'),
  ('EC_AI_MILITARY_HAS_HORSES', 'ResourceType', 'RESOURCE_HORSES'),
  ('EC_AI_MILITARY_HAS_NITER', 'ResourceType', 'RESOURCE_NITER'),
  ('EC_AI_MILITARY_HAS_COAL', 'ResourceType', 'RESOURCE_COAL'),
  ('EC_AI_MILITARY_HAS_OIL', 'ResourceType', 'RESOURCE_OIL'),
  ('EC_AI_MILITARY_HAS_ALUMINUM', 'ResourceType', 'RESOURCE_ALUMINUM'),
  ('EC_AI_MILITARY_HAS_URANIUM', 'ResourceType', 'RESOURCE_URANIUM');

INSERT OR IGNORE INTO RequirementSetRequirements (RequirementSetId, RequirementId)
VALUES
  ('EC_AI_MILITARY_RESOURCE_ANY', 'EC_AI_MILITARY_HAS_IRON'),
  ('EC_AI_MILITARY_RESOURCE_ANY', 'EC_AI_MILITARY_HAS_HORSES'),
  ('EC_AI_MILITARY_RESOURCE_ANY', 'EC_AI_MILITARY_HAS_NITER'),
  ('EC_AI_MILITARY_RESOURCE_ANY', 'EC_AI_MILITARY_HAS_COAL'),
  ('EC_AI_MILITARY_RESOURCE_ANY', 'EC_AI_MILITARY_HAS_OIL'),
  ('EC_AI_MILITARY_RESOURCE_ANY', 'EC_AI_MILITARY_HAS_ALUMINUM'),
  ('EC_AI_MILITARY_RESOURCE_ANY', 'EC_AI_MILITARY_HAS_URANIUM');

INSERT OR IGNORE INTO Modifiers (ModifierId, ModifierType, SubjectRequirementSetId)
VALUES
  ('EC_AI_MILITARY_UPGRADE_BASE', 'MODIFIER_PLAYER_ADJUST_UNIT_UPGRADE_DISCOUNT_PERCENT', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_UPGRADE_WARTIME', 'MODIFIER_PLAYER_ADJUST_UNIT_UPGRADE_DISCOUNT_PERCENT', 'EC_AI_MILITARY_WARTIME_OWNER'),
  -- Gathering Storm exposes the native strategic-resource upgrade-cost
  -- modifier. Keep a modest AI-only baseline and a second wartime layer so
  -- modern unit upgrades consume fewer strategic resources while mobilizing.
  ('EC_AI_MILITARY_UPGRADE_RESOURCE_BASE', 'MODIFIER_PLAYER_ADJUST_UNIT_UPGRADE_RESOURCE_COST_MODIFIER', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_UPGRADE_RESOURCE_WARTIME', 'MODIFIER_PLAYER_ADJUST_UNIT_UPGRADE_RESOURCE_COST_MODIFIER', 'EC_AI_MILITARY_WARTIME_OWNER'),
  -- Gathering Storm also exposes per-resource accumulation. A small AI-only
  -- baseline and wartime increment keep strategic resources available for
  -- unit training and upgrades without changing the human player's stockpile.
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_IRON', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_HORSES', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_NITER', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_COAL', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_OIL', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_ALUMINUM', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_URANIUM', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_IRON', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_HORSES', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_NITER', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_COAL', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_OIL', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_ALUMINUM', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_URANIUM', 'MODIFIER_PLAYER_ADJUST_RESOURCE_ACCUMULATION_MODIFIER', 'EC_AI_MILITARY_WARTIME_OWNER'),
  -- Gathering Storm also exposes a city-scoped accumulation effect. These
  -- small AI-only layers mirror RHAI's mature strategic-resource support;
  -- the wartime rows add one further unit of each resource per city while
  -- the known-war gate is active.
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_IRON', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_HORSES', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_NITER', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_COAL', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_OIL', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_ALUMINUM', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_URANIUM', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_IRON', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_HORSES', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_NITER', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_COAL', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_OIL', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_ALUMINUM', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_WARTIME_OWNER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_URANIUM', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_WARTIME_OWNER'),
  -- RHAI's technology-gated city tier restores additional modern resource
  -- throughput as military technologies become available.
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_HORSES', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_TECH_GATE'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_IRON', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_TECH_GATE'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_NITER', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_INDUSTRIALIZATION'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_COAL', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_CHEMISTRY'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_OIL', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_CHEMISTRY'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_ALUMINUM', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_CHEMISTRY'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_URANIUM', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_NUCLEAR_FUSION'),
  -- RHAI's late tier uses Industrialization, Chemistry and Combined Arms to
  -- keep modern AI armies supplied after the midgame resource tier.
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_HORSES', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_INDUSTRIALIZATION'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_IRON', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_INDUSTRIALIZATION'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_NITER', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_CHEMISTRY'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_COAL', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_COMBINED_ARMS'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_OIL', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_COMBINED_ARMS'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_ALUMINUM', 'MODIFIER_PLAYER_CITIES_ADJUST_EXTRA_ACCUMULATION_SPECIFIC_RESOURCE', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_COMBINED_ARMS'),
  -- RHAI's city requirement layer reduces the strategic-resource cost of
  -- units trained in AI cities. Attach the native city modifier once per AI
  -- city; keep the child modifier un-gated so the parent controls ownership.
  ('EC_AI_MILITARY_CITY_RESOURCE_REQUIREMENT_DISCOUNT', 'MODIFIER_PLAYER_CITIES_ATTACH_MODIFIER', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_CITY_RESOURCE_REQUIREMENT_DISCOUNT_EFFECT', 'MODIFIER_CITY_ADJUST_STRATEGIC_RESOURCE_REQUIREMENT_MODIFIER', NULL),
  -- Keep the accumulated strategic stockpile from saturating the native cap;
  -- this bounded owner-level lift gives AI players room to train, upgrade and
  -- purchase more units without creating units or changing human players.
  ('EC_AI_MILITARY_RESOURCE_STOCKPILE_CAP', 'MODIFIER_PLAYER_ADJUST_RESOURCE_STOCKPILE_CAP', 'PLAYER_IS_AI'),
  -- Accelerate the military district and its buildings for AI cities in both
  -- preparation and war. The district filter keeps the bonus focused on the
  -- encampment chain instead of raising every building's production.
  ('EC_AI_MILITARY_ENCAMPMENT_PRODUCTION', 'MODIFIER_PLAYER_CITIES_ADJUST_DISTRICT_PRODUCTION', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_ENCAMPMENT_BUILDINGS_PRODUCTION', 'MODIFIER_PLAYER_CITIES_ADJUST_BUILDING_PRODUCTION', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_MAINTENANCE_BASE', 'MODIFIER_PLAYER_ADJUST_UNIT_MAINTENANCE_DISCOUNT', 'PLAYER_IS_AI'),
  ('EC_AI_MILITARY_MAINTENANCE_TECH', 'MODIFIER_PLAYER_ADJUST_UNIT_MAINTENANCE_DISCOUNT', 'EC_AI_MILITARY_TECH_GATE'),
  ('EC_AI_MILITARY_MAINTENANCE_HIGH', 'MODIFIER_PLAYER_ADJUST_UNIT_MAINTENANCE_DISCOUNT', 'PLAYER_IS_HIGH_DIFFICULTY_AI'),
  ('EC_AI_MILITARY_MAINTENANCE_RESOURCE', 'MODIFIER_PLAYER_ADJUST_UNIT_MAINTENANCE_DISCOUNT', 'EC_AI_MILITARY_RESOURCE_ANY'),
  ('EC_AI_MILITARY_MAINTENANCE_WARTIME', 'MODIFIER_PLAYER_ADJUST_UNIT_MAINTENANCE_DISCOUNT', 'EC_AI_MILITARY_WARTIME_OWNER');

-- Strategic-resource production relief: once an AI controls at least one
-- native military strategic resource, let it convert that resource access into
-- a small additional military-unit production bonus. The AI owner gate keeps
-- this subject requirement from affecting human players.
INSERT OR IGNORE INTO Modifiers
  (ModifierId, ModifierType, OwnerRequirementSetId, SubjectRequirementSetId)
VALUES
  ('EC_AI_MILITARY_PRODUCTION_RESOURCE',
   'MODIFIER_PLAYER_CITIES_ADJUST_MILITARY_UNITS_PRODUCTION',
   'PLAYER_IS_AI', 'EC_AI_MILITARY_RESOURCE_ANY');

-- During a known war, let the same strategic-resource access provide a
-- stronger replenishment surge. Reuse the existing wartime owner gate so the
-- extra production is unavailable in peace and remains AI-only.
INSERT OR IGNORE INTO Modifiers
  (ModifierId, ModifierType, OwnerRequirementSetId, SubjectRequirementSetId)
VALUES
  ('EC_AI_MILITARY_PRODUCTION_WARTIME_RESOURCE',
   'MODIFIER_PLAYER_CITIES_ADJUST_MILITARY_UNITS_PRODUCTION',
   'EC_AI_MILITARY_WARTIME_OWNER', 'EC_AI_MILITARY_RESOURCE_ANY');

-- Late-war air composition: RHAI uses the native unit-tag/era production
-- modifier for bombers. Keep the amount bounded and require the existing
-- known-war AI gate so this only fills an active information-era air gap.
INSERT OR IGNORE INTO Modifiers
  (ModifierId, ModifierType, OwnerRequirementSetId)
VALUES
  ('EC_AI_MILITARY_WARTIME_AIR_BOMBER',
   'MODIFIER_PLAYER_CITIES_ADJUST_UNIT_TAG_ERA_PRODUCTION',
   'EC_AI_MILITARY_WARTIME_OWNER');

UPDATE Modifiers
SET OwnerRequirementSetId = 'PLAYER_IS_AI'
WHERE ModifierId = 'EC_AI_MILITARY_MAINTENANCE_RESOURCE';

INSERT OR IGNORE INTO ModifierArguments (ModifierId, Name, Value)
VALUES
  ('EC_AI_MILITARY_UPGRADE_BASE', 'Amount', 10),
  ('EC_AI_MILITARY_UPGRADE_WARTIME', 'Amount', 10),
  ('EC_AI_MILITARY_UPGRADE_RESOURCE_BASE', 'Amount', 20),
  ('EC_AI_MILITARY_UPGRADE_RESOURCE_WARTIME', 'Amount', 20),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_IRON', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_IRON', 'ResourceType', 'RESOURCE_IRON'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_HORSES', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_HORSES', 'ResourceType', 'RESOURCE_HORSES'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_NITER', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_NITER', 'ResourceType', 'RESOURCE_NITER'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_COAL', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_COAL', 'ResourceType', 'RESOURCE_COAL'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_OIL', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_OIL', 'ResourceType', 'RESOURCE_OIL'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_ALUMINUM', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_ALUMINUM', 'ResourceType', 'RESOURCE_ALUMINUM'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_URANIUM', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_URANIUM', 'ResourceType', 'RESOURCE_URANIUM'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_IRON', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_IRON', 'ResourceType', 'RESOURCE_IRON'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_HORSES', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_HORSES', 'ResourceType', 'RESOURCE_HORSES'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_NITER', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_NITER', 'ResourceType', 'RESOURCE_NITER'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_COAL', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_COAL', 'ResourceType', 'RESOURCE_COAL'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_OIL', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_OIL', 'ResourceType', 'RESOURCE_OIL'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_ALUMINUM', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_ALUMINUM', 'ResourceType', 'RESOURCE_ALUMINUM'),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_URANIUM', 'Amount', 1),
  ('EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_URANIUM', 'ResourceType', 'RESOURCE_URANIUM'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_IRON', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_IRON', 'ResourceType', 'RESOURCE_IRON'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_HORSES', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_HORSES', 'ResourceType', 'RESOURCE_HORSES'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_NITER', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_NITER', 'ResourceType', 'RESOURCE_NITER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_COAL', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_COAL', 'ResourceType', 'RESOURCE_COAL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_OIL', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_OIL', 'ResourceType', 'RESOURCE_OIL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_ALUMINUM', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_ALUMINUM', 'ResourceType', 'RESOURCE_ALUMINUM'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_URANIUM', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_URANIUM', 'ResourceType', 'RESOURCE_URANIUM'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_IRON', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_IRON', 'ResourceType', 'RESOURCE_IRON'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_HORSES', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_HORSES', 'ResourceType', 'RESOURCE_HORSES'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_NITER', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_NITER', 'ResourceType', 'RESOURCE_NITER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_COAL', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_COAL', 'ResourceType', 'RESOURCE_COAL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_OIL', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_OIL', 'ResourceType', 'RESOURCE_OIL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_ALUMINUM', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_ALUMINUM', 'ResourceType', 'RESOURCE_ALUMINUM'),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_URANIUM', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_URANIUM', 'ResourceType', 'RESOURCE_URANIUM'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_HORSES', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_HORSES', 'ResourceType', 'RESOURCE_HORSES'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_IRON', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_IRON', 'ResourceType', 'RESOURCE_IRON'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_NITER', 'Amount', 2),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_NITER', 'ResourceType', 'RESOURCE_NITER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_COAL', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_COAL', 'ResourceType', 'RESOURCE_COAL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_OIL', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_OIL', 'ResourceType', 'RESOURCE_OIL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_ALUMINUM', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_ALUMINUM', 'ResourceType', 'RESOURCE_ALUMINUM'),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_URANIUM', 'Amount', 2),
  ('EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_URANIUM', 'ResourceType', 'RESOURCE_URANIUM'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_HORSES', 'Amount', 2),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_HORSES', 'ResourceType', 'RESOURCE_HORSES'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_IRON', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_IRON', 'ResourceType', 'RESOURCE_IRON'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_NITER', 'Amount', 2),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_NITER', 'ResourceType', 'RESOURCE_NITER'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_COAL', 'Amount', 2),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_COAL', 'ResourceType', 'RESOURCE_COAL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_OIL', 'Amount', 2),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_OIL', 'ResourceType', 'RESOURCE_OIL'),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_ALUMINUM', 'Amount', 1),
  ('EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_ALUMINUM', 'ResourceType', 'RESOURCE_ALUMINUM'),
  ('EC_AI_MILITARY_CITY_RESOURCE_REQUIREMENT_DISCOUNT', 'ModifierId', 'EC_AI_MILITARY_CITY_RESOURCE_REQUIREMENT_DISCOUNT_EFFECT'),
  ('EC_AI_MILITARY_CITY_RESOURCE_REQUIREMENT_DISCOUNT_EFFECT', 'Amount', 20),
  ('EC_AI_MILITARY_RESOURCE_STOCKPILE_CAP', 'Amount', 10),
  ('EC_AI_MILITARY_ENCAMPMENT_PRODUCTION', 'DistrictType', 'DISTRICT_ENCAMPMENT'),
  ('EC_AI_MILITARY_ENCAMPMENT_PRODUCTION', 'Amount', 15),
  ('EC_AI_MILITARY_ENCAMPMENT_BUILDINGS_PRODUCTION', 'DistrictType', 'DISTRICT_ENCAMPMENT'),
  ('EC_AI_MILITARY_ENCAMPMENT_BUILDINGS_PRODUCTION', 'Amount', 15),
  ('EC_AI_MILITARY_MAINTENANCE_BASE', 'Amount', 1),
  ('EC_AI_MILITARY_MAINTENANCE_TECH', 'Amount', 1),
  ('EC_AI_MILITARY_MAINTENANCE_HIGH', 'Amount', 1),
  ('EC_AI_MILITARY_MAINTENANCE_RESOURCE', 'Amount', 1),
  ('EC_AI_MILITARY_MAINTENANCE_WARTIME', 'Amount', 1),
  ('EC_AI_MILITARY_PRODUCTION_RESOURCE', 'Amount', 2),
  ('EC_AI_MILITARY_PRODUCTION_WARTIME_RESOURCE', 'Amount', 4);

INSERT OR IGNORE INTO ModifierArguments (ModifierId, Name, Value, Extra)
VALUES
  ('EC_AI_MILITARY_WARTIME_AIR_BOMBER', 'UnitPromotionClass', 'PROMOTION_CLASS_AIR_BOMBER', -1),
  ('EC_AI_MILITARY_WARTIME_AIR_BOMBER', 'EraType', 'ERA_INFORMATION', -1),
  ('EC_AI_MILITARY_WARTIME_AIR_BOMBER', 'Amount', 20, -1);

INSERT OR IGNORE INTO TraitModifiers (TraitType, ModifierId)
VALUES
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_UPGRADE_BASE'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_UPGRADE_WARTIME'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_UPGRADE_RESOURCE_BASE'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_UPGRADE_RESOURCE_WARTIME'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_IRON'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_HORSES'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_NITER'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_COAL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_OIL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_ALUMINUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_URANIUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_IRON'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_HORSES'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_NITER'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_COAL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_OIL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_ALUMINUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_ACCUMULATION_WARTIME_URANIUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_IRON'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_HORSES'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_NITER'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_COAL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_OIL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_ALUMINUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_URANIUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_IRON'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_HORSES'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_NITER'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_COAL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_OIL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_ALUMINUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_ACCUMULATION_WARTIME_URANIUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_HORSES'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_IRON'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_NITER'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_COAL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_OIL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_ALUMINUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_TECH_ACCUMULATION_URANIUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_HORSES'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_IRON'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_NITER'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_COAL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_OIL'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_LATE_ACCUMULATION_ALUMINUM'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_CITY_RESOURCE_REQUIREMENT_DISCOUNT'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_RESOURCE_STOCKPILE_CAP'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_ENCAMPMENT_PRODUCTION'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_ENCAMPMENT_BUILDINGS_PRODUCTION'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_MAINTENANCE_BASE'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_MAINTENANCE_TECH'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_MAINTENANCE_HIGH'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_MAINTENANCE_RESOURCE'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_MAINTENANCE_WARTIME'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_PRODUCTION_RESOURCE'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_PRODUCTION_WARTIME_RESOURCE'),
  ('TRAIT_LEADER_MAJOR_CIV', 'EC_AI_MILITARY_WARTIME_AIR_BOMBER');

-- Immediate response to a threatened city. RHAI uses the native
-- "Cities Under Threat" strategy condition for this short-lived layer; keep
-- the response bounded and defensive so it supplements, rather than replaces,
-- the general pre-war and at-war strategies.
INSERT OR IGNORE INTO Strategies (StrategyType, NumConditionsNeeded)
VALUES ('STRATEGY_UNDER_ATTACK', 1);

INSERT OR IGNORE INTO StrategyConditions
  (StrategyType, ConditionFunction, ThresholdValue)
VALUES ('STRATEGY_UNDER_ATTACK', 'Cities Under Threat', 1);

INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES
  ('EC_AI_MILITARY_UNDER_ATTACK_YIELDS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_SPECIALISE'),
  ('EC_AI_MILITARY_UNDER_ATTACK_BUILDINGS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_DISTRICTS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_OPERATIONS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_PER_WAR_OPERATIONS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_CITY_EVENTS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS'),
  ('EC_AI_MILITARY_UNDER_ATTACK_SAVINGS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES
  ('EC_AI_MILITARY_UNDER_ATTACK_YIELDS', 'Yields'),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS', 'PseudoYields'),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'UnitPromotionClasses'),
  ('EC_AI_MILITARY_UNDER_ATTACK_SPECIALISE', 'AiBuildSpecializations'),
  ('EC_AI_MILITARY_UNDER_ATTACK_BUILDINGS', 'Buildings'),
  ('EC_AI_MILITARY_UNDER_ATTACK_DISTRICTS', 'Districts'),
  ('EC_AI_MILITARY_UNDER_ATTACK_OPERATIONS', 'AiOperationTypes'),
  ('EC_AI_MILITARY_UNDER_ATTACK_PER_WAR_OPERATIONS', 'PerWarOperationTypes'),
  ('EC_AI_MILITARY_UNDER_ATTACK_CITY_EVENTS', 'CityEvents'),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'Technologies'),
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS', 'Civics'),
  ('EC_AI_MILITARY_UNDER_ATTACK_SAVINGS', 'SavingTypes');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_YIELDS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_SPECIALISE'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_BUILDINGS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_DISTRICTS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_OPERATIONS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_PER_WAR_OPERATIONS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_CITY_EVENTS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_TECHS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_CIVICS'),
  ('STRATEGY_UNDER_ATTACK', 'EC_AI_MILITARY_UNDER_ATTACK_SAVINGS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_UNDER_ATTACK_YIELDS', 'YIELD_PRODUCTION', 30),
  -- Emergency defense follows RHAI's aggressive gold preference, bounded at 10.
  ('EC_AI_MILITARY_UNDER_ATTACK_YIELDS', 'YIELD_GOLD', 10),
  -- RHAI's emergency layer uses -2 so threatened AI spends reserved gold on units.
  ('EC_AI_MILITARY_UNDER_ATTACK_SAVINGS', 'SAVING_UNITS', -2),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS', 'PSEUDOYIELD_UNIT_COMBAT', 12),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS', 'PSEUDOYIELD_UNIT_NAVAL_COMBAT', 8),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS', 'PSEUDOYIELD_UNIT_AIR_COMBAT', 8),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_NUMBER', 14),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS', 'PSEUDOYIELD_GPP_GENERAL', 80),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_VALUE', 10),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENSES', 14),
  ('EC_AI_MILITARY_UNDER_ATTACK_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENDING_UNITS', 12),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'PROMOTION_CLASS_MELEE', 3),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'PROMOTION_CLASS_RANGED', 3),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'PROMOTION_CLASS_SIEGE', 4),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'PROMOTION_CLASS_ANTI_CAVALRY', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'PROMOTION_CLASS_HEAVY_CAVALRY', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'PROMOTION_CLASS_SUPPORT', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'PROMOTION_CLASS_NAVAL_RANGED', 2),
  -- R93: RHAI's DefensiveUnitBuilds uses air fighters for emergency
  -- interception; keep the native class preference bounded below bombers.
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'PROMOTION_CLASS_AIR_FIGHTER', 3),
  ('EC_AI_MILITARY_UNDER_ATTACK_UNIT_BUILDS', 'PROMOTION_CLASS_AIR_BOMBER', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_SPECIALISE', 'BUILD_MILITARY_UNITS', 4),
  ('EC_AI_MILITARY_UNDER_ATTACK_SPECIALISE', 'BUILD_CITY_DEFENSES', 3),
  ('EC_AI_MILITARY_UNDER_ATTACK_BUILDINGS', 'BUILDING_BARRACKS', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_BUILDINGS', 'BUILDING_STABLE', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_BUILDINGS', 'BUILDING_ARMORY', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_BUILDINGS', 'BUILDING_MILITARY_ACADEMY', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_DISTRICTS', 'DISTRICT_ENCAMPMENT', 5),
  ('EC_AI_MILITARY_UNDER_ATTACK_DISTRICTS', 'DISTRICT_AERODROME', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_OPERATIONS', 'OP_DEFENSE', 2),
  ('EC_AI_MILITARY_UNDER_ATTACK_PER_WAR_OPERATIONS', 'OP_DEFENSE', 2);

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, StringVal)
VALUES
  ('EC_AI_MILITARY_UNDER_ATTACK_CITY_EVENTS', 'CITY_EVENT_DEFAULT', 'Upgrade Units'),
  ('EC_AI_MILITARY_UNDER_ATTACK_CITY_EVENTS', 'CITY_UNDER_THREAT', 'Upgrade Units');

-- Emergency technology path for threatened cities. Keep the same native
-- technology identifiers used by the wartime and late-game layers, with
-- bounded weights so this short-lived response still leaves room for normal
-- economic and victory research.
INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_MILITARY_ENGINEERING', 4),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_METAL_CASTING', 4),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_MILITARY_SCIENCE', 5),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_COMBUSTION', 5),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_COMBINED_ARMS', 5),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_ADVANCED_FLIGHT', 4),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_STEALTH_TECHNOLOGY', 4),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_NUCLEAR_FISSION', 4),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_NUCLEAR_FUSION', 4),
  ('EC_AI_MILITARY_UNDER_ATTACK_TECHS', 'TECH_ROBOTICS', 4);

-- Emergency civic path. A threatened city should favor defensive and
-- mobilization civics while the native Cities Under Threat strategy is active;
-- keep the values bounded and leave civic costs/prerequisites untouched.
INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS', 'CIVIC_MILITARY_TRADITION', 5),
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS', 'CIVIC_MILITARY_TRAINING', 5),
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS', 'CIVIC_DEFENSIVE_TACTICS', 6),
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS', 'CIVIC_MERCENARIES', 5),
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS', 'CIVIC_NATIONALISM', 5),
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS', 'CIVIC_SCORCHED_EARTH', 6),
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS', 'CIVIC_MOBILIZATION', 7),
  ('EC_AI_MILITARY_UNDER_ATTACK_CIVICS', 'CIVIC_RAPID_DEPLOYMENT', 7);

-- Industrial/Modern-era military layer. The base game exposes these era
-- conditions through STRATEGY_INDUSTRIAL_CHANGES and
-- STRATEGY_MODERN_CHANGES; keep this project-specific strategy separate so
-- other era behavior and other AI overhauls are not overwritten. This is a
-- bounded late-game preference layer, not a direct unit-spawn mechanism.
INSERT OR IGNORE INTO Strategies (StrategyType, NumConditionsNeeded)
VALUES ('STRATEGY_EC_MILITARY_LATE', 1);

INSERT OR IGNORE INTO StrategyConditions
  (StrategyType, ConditionFunction, ThresholdValue, Disqualifier)
VALUES
  ('STRATEGY_EC_MILITARY_LATE', 'Is Industrial', 1, 0),
  ('STRATEGY_EC_MILITARY_LATE', 'Is Modern', 1, 0),
  ('STRATEGY_EC_MILITARY_LATE', 'Is Not Major', 0, 1);

INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES
  ('EC_AI_MILITARY_LATE_YIELDS'),
  ('EC_AI_MILITARY_LATE_PSEUDOS'),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS'),
  ('EC_AI_MILITARY_LATE_SPECIALISE'),
  ('EC_AI_MILITARY_LATE_BUILDINGS'),
  ('EC_AI_MILITARY_LATE_DISTRICTS'),
  ('EC_AI_MILITARY_LATE_OPERATIONS'),
  ('EC_AI_MILITARY_LATE_PER_WAR_OPERATIONS'),
  ('EC_AI_MILITARY_LATE_CITY_EVENTS'),
  ('EC_AI_MILITARY_LATE_TECHS'),
  ('EC_AI_MILITARY_LATE_CIVICS'),
  ('EC_AI_MILITARY_LATE_SAVINGS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES
  ('EC_AI_MILITARY_LATE_YIELDS', 'Yields'),
  ('EC_AI_MILITARY_LATE_PSEUDOS', 'PseudoYields'),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS', 'UnitPromotionClasses'),
  ('EC_AI_MILITARY_LATE_SPECIALISE', 'AiBuildSpecializations'),
  ('EC_AI_MILITARY_LATE_BUILDINGS', 'Buildings'),
  ('EC_AI_MILITARY_LATE_DISTRICTS', 'Districts'),
  ('EC_AI_MILITARY_LATE_OPERATIONS', 'AiOperationTypes'),
  ('EC_AI_MILITARY_LATE_PER_WAR_OPERATIONS', 'PerWarOperationTypes'),
  ('EC_AI_MILITARY_LATE_CITY_EVENTS', 'CityEvents'),
  ('EC_AI_MILITARY_LATE_TECHS', 'Technologies'),
  ('EC_AI_MILITARY_LATE_CIVICS', 'Civics'),
  ('EC_AI_MILITARY_LATE_SAVINGS', 'SavingTypes');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_YIELDS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_PSEUDOS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_UNIT_BUILDS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_SPECIALISE'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_BUILDINGS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_DISTRICTS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_OPERATIONS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_PER_WAR_OPERATIONS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_CITY_EVENTS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_TECHS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_CIVICS'),
  ('STRATEGY_EC_MILITARY_LATE', 'EC_AI_MILITARY_LATE_SAVINGS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_LATE_YIELDS', 'YIELD_PRODUCTION', 20),
  -- R92: the late strategy already reserves unit funds and favors military
  -- production; add a bounded cash-flow preference for late purchases while
  -- staying below the active-war (8) and under-attack (10) gold layers.
  ('EC_AI_MILITARY_LATE_YIELDS', 'YIELD_GOLD', 4),
  ('EC_AI_MILITARY_LATE_PSEUDOS', 'PSEUDOYIELD_UNIT_COMBAT', 8),
  ('EC_AI_MILITARY_LATE_PSEUDOS', 'PSEUDOYIELD_UNIT_NAVAL_COMBAT', 8),
  ('EC_AI_MILITARY_LATE_PSEUDOS', 'PSEUDOYIELD_UNIT_AIR_COMBAT', 8),
  ('EC_AI_MILITARY_LATE_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_NUMBER', 12),
  ('EC_AI_MILITARY_LATE_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_VALUE', 8),
  ('EC_AI_MILITARY_LATE_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENSES', 8),
  ('EC_AI_MILITARY_LATE_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENDING_UNITS', 6),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_MELEE', 3),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_RANGED', 3),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_SIEGE', 4),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_ANTI_CAVALRY', 2),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_HEAVY_CAVALRY', 2),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_SUPPORT', 2),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_NAVAL_RANGED', 2),
  ('EC_AI_MILITARY_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_AIR_BOMBER', 3),
  ('EC_AI_MILITARY_LATE_SPECIALISE', 'BUILD_MILITARY_UNITS', 3),
  ('EC_AI_MILITARY_LATE_SPECIALISE', 'BUILD_CITY_DEFENSES', 2),
  ('EC_AI_MILITARY_LATE_BUILDINGS', 'BUILDING_BARRACKS', 2),
  ('EC_AI_MILITARY_LATE_BUILDINGS', 'BUILDING_STABLE', 2),
  ('EC_AI_MILITARY_LATE_BUILDINGS', 'BUILDING_ARMORY', 2),
  ('EC_AI_MILITARY_LATE_BUILDINGS', 'BUILDING_MILITARY_ACADEMY', 2),
  ('EC_AI_MILITARY_LATE_DISTRICTS', 'DISTRICT_ENCAMPMENT', 4),
  ('EC_AI_MILITARY_LATE_DISTRICTS', 'DISTRICT_AERODROME', 2),
  ('EC_AI_MILITARY_LATE_OPERATIONS', 'CITY_ASSAULT', 1),
  ('EC_AI_MILITARY_LATE_OPERATIONS', 'OP_DEFENSE', 1),
  ('EC_AI_MILITARY_LATE_PER_WAR_OPERATIONS', 'CITY_ASSAULT', 1),
  ('EC_AI_MILITARY_LATE_PER_WAR_OPERATIONS', 'OP_DEFENSE', 1),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_MILITARY_ENGINEERING', 4),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_METAL_CASTING', 4),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_MILITARY_SCIENCE', 5),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_COMBUSTION', 5),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_COMBINED_ARMS', 6),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_ADVANCED_FLIGHT', 5),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_STEALTH_TECHNOLOGY', 5),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_NUCLEAR_FISSION', 5),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_NUCLEAR_FUSION', 5),
  ('EC_AI_MILITARY_LATE_TECHS', 'TECH_ROBOTICS', 5),
  -- R89: preserve the native RHAI unit-funding direction in the late
  -- military strategy so industrial/modern AI can spend on units sooner.
  ('EC_AI_MILITARY_LATE_SAVINGS', 'SAVING_UNITS', 3);

-- Late-era civic path. Keep these below the active-war weights so industrial
-- and modern AI can prepare a military policy tree without making military
-- civics a global priority during every peaceful turn.
INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_LATE_CIVICS', 'CIVIC_MILITARY_TRADITION', 3),
  ('EC_AI_MILITARY_LATE_CIVICS', 'CIVIC_MILITARY_TRAINING', 3),
  ('EC_AI_MILITARY_LATE_CIVICS', 'CIVIC_DEFENSIVE_TACTICS', 3),
  ('EC_AI_MILITARY_LATE_CIVICS', 'CIVIC_MERCENARIES', 3),
  ('EC_AI_MILITARY_LATE_CIVICS', 'CIVIC_NATIONALISM', 4),
  ('EC_AI_MILITARY_LATE_CIVICS', 'CIVIC_SCORCHED_EARTH', 3),
  ('EC_AI_MILITARY_LATE_CIVICS', 'CIVIC_MOBILIZATION', 5),
  ('EC_AI_MILITARY_LATE_CIVICS', 'CIVIC_RAPID_DEPLOYMENT', 5);

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, StringVal)
VALUES
  ('EC_AI_MILITARY_LATE_CITY_EVENTS', 'CITY_EVENT_DEFAULT', 'Upgrade Units'),
  ('EC_AI_MILITARY_LATE_CITY_EVENTS', 'CITY_UNDER_THREAT', 'Upgrade Units');

-- RHAI also defines a very-high-strength late strategy. Its Atomic and
-- Information-era condition names are not present in this Steam build, so
-- keep only the native condition subset and require four strong signals.
-- The lists below are composition and production preferences for already
-- dominant AI; they do not add production modifiers, diplomacy, operations
-- or direct spawns. The native production yield is deliberately bounded and
-- only applies after the late strategy's four-signal gate is satisfied.
INSERT OR IGNORE INTO Strategies (StrategyType, NumConditionsNeeded)
VALUES ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 4);

INSERT OR IGNORE INTO StrategyConditions
  (StrategyType, ConditionFunction, ThresholdValue, Forbidden, Disqualifier)
VALUES
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'Leads Military', 33, 0, 0),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'Has Tech Lead', 25, 0, 0),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'Leads Score', 25, 0, 0),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'Next Lower Score', 350, 0, 0),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'Has Taken Capital', 1, 0, 0),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'Is Industrial', 1, 0, 0),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'Is Modern', 1, 0, 0),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'Tourists Taken', 200, 1, 0),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'Is Not Major', 0, 0, 1);

INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES
  ('EC_AI_MILITARY_VERY_HIGH_LATE_YIELDS'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PSEUDOS'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_UNIT_BUILDS'),
  -- R94: dominant late AI also needs explicit military research/policy paths.
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS'),
  -- R95: use the same native infrastructure/specialization systems as the
  -- ordinary late layer, but only after the very-high four-signal gate.
  ('EC_AI_MILITARY_VERY_HIGH_LATE_SPECIALISE'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_BUILDINGS'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_DISTRICTS'),
  -- R96: dominant late AI receives explicit war-operation and city-upgrade
  -- inputs, still isolated behind the existing four-signal strategy gate.
  ('EC_AI_MILITARY_VERY_HIGH_LATE_OPERATIONS'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PER_WAR_OPERATIONS'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CITY_EVENTS'),
  -- R97: RHAI AggressiveSavings spends dominant late AI funds on units now.
  ('EC_AI_MILITARY_VERY_HIGH_LATE_SAVINGS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES
  ('EC_AI_MILITARY_VERY_HIGH_LATE_YIELDS', 'Yields'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PSEUDOS', 'PseudoYields'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_UNIT_BUILDS', 'UnitPromotionClasses'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'Technologies'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS', 'Civics'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_SPECIALISE', 'AiBuildSpecializations'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_BUILDINGS', 'Buildings'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_DISTRICTS', 'Districts'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_OPERATIONS', 'AiOperationTypes'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PER_WAR_OPERATIONS', 'PerWarOperationTypes'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CITY_EVENTS', 'CityEvents'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_SAVINGS', 'SavingTypes');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_YIELDS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_PSEUDOS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_UNIT_BUILDS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_TECHS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_SPECIALISE'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_BUILDINGS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_DISTRICTS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_OPERATIONS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_PER_WAR_OPERATIONS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_CITY_EVENTS'),
  ('STRATEGY_EC_MILITARY_VERY_HIGH_LATE', 'EC_AI_MILITARY_VERY_HIGH_LATE_SAVINGS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_VERY_HIGH_LATE_YIELDS', 'YIELD_PRODUCTION', 25),
  -- R100: the mature RHAI aggressive layer also keeps a bounded gold preference.
  ('EC_AI_MILITARY_VERY_HIGH_LATE_YIELDS', 'YIELD_GOLD', 10),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PSEUDOS', 'PSEUDOYIELD_UNIT_COMBAT', 20),
  -- R102: match the mature aggressive naval/air evaluation profile.
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PSEUDOS', 'PSEUDOYIELD_UNIT_NAVAL_COMBAT', 65),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PSEUDOS', 'PSEUDOYIELD_UNIT_AIR_COMBAT', 40),
  -- R101: match the mature aggressive army-size/value direction.
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_NUMBER', 27),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_VALUE', 16),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_SIEGE', 3),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_UNIT_BUILDS', 'PROMOTION_CLASS_AIR_BOMBER', 10),
  -- Keep this stronger than ordinary late/wartime research, but bounded and
  -- limited to the four-signal dominant-AI strategy.
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_MILITARY_ENGINEERING', 6),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_METAL_CASTING', 6),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_MILITARY_SCIENCE', 7),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_COMBUSTION', 7),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_COMBINED_ARMS', 8),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_ADVANCED_FLIGHT', 7),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_STEALTH_TECHNOLOGY', 7),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_NUCLEAR_FISSION', 7),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_NUCLEAR_FUSION', 7),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_TECHS', 'TECH_ROBOTICS', 7),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS', 'CIVIC_MILITARY_TRADITION', 5),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS', 'CIVIC_MILITARY_TRAINING', 5),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS', 'CIVIC_DEFENSIVE_TACTICS', 5),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS', 'CIVIC_MERCENARIES', 5),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS', 'CIVIC_NATIONALISM', 6),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS', 'CIVIC_SCORCHED_EARTH', 5),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS', 'CIVIC_MOBILIZATION', 7),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CIVICS', 'CIVIC_RAPID_DEPLOYMENT', 7),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_SPECIALISE', 'BUILD_MILITARY_UNITS', 5),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_SPECIALISE', 'BUILD_CITY_DEFENSES', 4),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_BUILDINGS', 'BUILDING_BARRACKS', 3),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_BUILDINGS', 'BUILDING_STABLE', 3),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_BUILDINGS', 'BUILDING_ARMORY', 3),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_BUILDINGS', 'BUILDING_MILITARY_ACADEMY', 3),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_DISTRICTS', 'DISTRICT_ENCAMPMENT', 5),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_DISTRICTS', 'DISTRICT_AERODROME', 3),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_OPERATIONS', 'CITY_ASSAULT', 2),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_OPERATIONS', 'OP_DEFENSE', 2),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PER_WAR_OPERATIONS', 'CITY_ASSAULT', 1),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_PER_WAR_OPERATIONS', 'OP_DEFENSE', 1),
  -- Keep the RHAI aggressive spending direction isolated to the four-signal
  -- dominant-AI strategy; ordinary late AI still uses SAVING_UNITS=3.
  ('EC_AI_MILITARY_VERY_HIGH_LATE_SAVINGS', 'SAVING_UNITS', -2);

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, StringVal)
VALUES
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CITY_EVENTS', 'CITY_EVENT_DEFAULT', 'Upgrade Units'),
  ('EC_AI_MILITARY_VERY_HIGH_LATE_CITY_EVENTS', 'CITY_UNDER_THREAT', 'Upgrade Units');

-- Military recovery layer. The native Lags Military condition is used by the
-- base science-victory strategy; reuse that proven condition to make a major
-- AI that falls behind militarily invest in recovery before a war starts.
-- These are bounded preferences only and do not create units directly.
INSERT OR IGNORE INTO Strategies (StrategyType, NumConditionsNeeded)
VALUES ('STRATEGY_EC_MILITARY_BEHIND', 1);

INSERT OR IGNORE INTO StrategyConditions
  (StrategyType, ConditionFunction, ThresholdValue, Disqualifier)
VALUES
  ('STRATEGY_EC_MILITARY_BEHIND', 'Lags Military', 33, 0),
  ('STRATEGY_EC_MILITARY_BEHIND', 'Is Not Major', 0, 1);

INSERT OR IGNORE INTO AiListTypes (ListType)
VALUES
  ('EC_AI_MILITARY_BEHIND_YIELDS'),
  ('EC_AI_MILITARY_BEHIND_PSEUDOS'),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS'),
  ('EC_AI_MILITARY_BEHIND_SPECIALISE'),
  ('EC_AI_MILITARY_BEHIND_BUILDINGS'),
  ('EC_AI_MILITARY_BEHIND_DISTRICTS'),
  ('EC_AI_MILITARY_BEHIND_OPERATIONS'),
  ('EC_AI_MILITARY_BEHIND_PER_WAR_OPERATIONS'),
  ('EC_AI_MILITARY_BEHIND_CITY_EVENTS'),
  ('EC_AI_MILITARY_BEHIND_CIVICS'),
  ('EC_AI_MILITARY_BEHIND_TECHS'),
  ('EC_AI_MILITARY_BEHIND_SAVINGS');

INSERT OR IGNORE INTO AiLists (ListType, System)
VALUES
  ('EC_AI_MILITARY_BEHIND_YIELDS', 'Yields'),
  ('EC_AI_MILITARY_BEHIND_PSEUDOS', 'PseudoYields'),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS', 'UnitPromotionClasses'),
  ('EC_AI_MILITARY_BEHIND_SPECIALISE', 'AiBuildSpecializations'),
  ('EC_AI_MILITARY_BEHIND_BUILDINGS', 'Buildings'),
  ('EC_AI_MILITARY_BEHIND_DISTRICTS', 'Districts'),
  ('EC_AI_MILITARY_BEHIND_OPERATIONS', 'AiOperationTypes'),
  ('EC_AI_MILITARY_BEHIND_PER_WAR_OPERATIONS', 'PerWarOperationTypes'),
  ('EC_AI_MILITARY_BEHIND_CITY_EVENTS', 'CityEvents'),
  ('EC_AI_MILITARY_BEHIND_CIVICS', 'Civics'),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'Technologies'),
  ('EC_AI_MILITARY_BEHIND_SAVINGS', 'SavingTypes');

INSERT OR IGNORE INTO Strategy_Priorities (StrategyType, ListType)
VALUES
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_YIELDS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_PSEUDOS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_UNIT_BUILDS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_SPECIALISE'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_BUILDINGS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_DISTRICTS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_OPERATIONS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_PER_WAR_OPERATIONS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_CITY_EVENTS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_CIVICS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_TECHS'),
  ('STRATEGY_EC_MILITARY_BEHIND', 'EC_AI_MILITARY_BEHIND_SAVINGS');

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_BEHIND_YIELDS', 'YIELD_PRODUCTION', 24),
  -- R91: preserve the bounded pre-war gold direction used by the strength
  -- layer so a militarily lagging AI can fund purchases before -2 emergency
  -- spending takes over. RHAI's AggressiveYields uses 10; 6 matches the
  -- existing strength layer and remains below active-war/under-attack gold.
  ('EC_AI_MILITARY_BEHIND_YIELDS', 'YIELD_GOLD', 6),
  ('EC_AI_MILITARY_BEHIND_PSEUDOS', 'PSEUDOYIELD_UNIT_COMBAT', 8),
  ('EC_AI_MILITARY_BEHIND_PSEUDOS', 'PSEUDOYIELD_UNIT_NAVAL_COMBAT', 6),
  ('EC_AI_MILITARY_BEHIND_PSEUDOS', 'PSEUDOYIELD_UNIT_AIR_COMBAT', 6),
  ('EC_AI_MILITARY_BEHIND_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_NUMBER', 12),
  ('EC_AI_MILITARY_BEHIND_PSEUDOS', 'PSEUDOYIELD_STANDING_ARMY_VALUE', 7),
  ('EC_AI_MILITARY_BEHIND_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENSES', 6),
  ('EC_AI_MILITARY_BEHIND_PSEUDOS', 'PSEUDOYIELD_CITY_DEFENDING_UNITS', 5),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS', 'PROMOTION_CLASS_MELEE', 3),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS', 'PROMOTION_CLASS_RANGED', 3),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS', 'PROMOTION_CLASS_SIEGE', 4),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS', 'PROMOTION_CLASS_ANTI_CAVALRY', 2),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS', 'PROMOTION_CLASS_HEAVY_CAVALRY', 2),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS', 'PROMOTION_CLASS_SUPPORT', 2),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS', 'PROMOTION_CLASS_NAVAL_RANGED', 2),
  ('EC_AI_MILITARY_BEHIND_UNIT_BUILDS', 'PROMOTION_CLASS_AIR_BOMBER', 2),
  ('EC_AI_MILITARY_BEHIND_SPECIALISE', 'BUILD_MILITARY_UNITS', 3),
  ('EC_AI_MILITARY_BEHIND_SPECIALISE', 'BUILD_CITY_DEFENSES', 2),
  ('EC_AI_MILITARY_BEHIND_BUILDINGS', 'BUILDING_BARRACKS', 2),
  ('EC_AI_MILITARY_BEHIND_BUILDINGS', 'BUILDING_STABLE', 2),
  ('EC_AI_MILITARY_BEHIND_BUILDINGS', 'BUILDING_ARMORY', 2),
  ('EC_AI_MILITARY_BEHIND_BUILDINGS', 'BUILDING_MILITARY_ACADEMY', 2),
  ('EC_AI_MILITARY_BEHIND_DISTRICTS', 'DISTRICT_ENCAMPMENT', 3),
  ('EC_AI_MILITARY_BEHIND_DISTRICTS', 'DISTRICT_AERODROME', 1),
  ('EC_AI_MILITARY_BEHIND_OPERATIONS', 'CITY_ASSAULT', 1),
  ('EC_AI_MILITARY_BEHIND_OPERATIONS', 'OP_DEFENSE', 1),
  ('EC_AI_MILITARY_BEHIND_PER_WAR_OPERATIONS', 'CITY_ASSAULT', 1),
  ('EC_AI_MILITARY_BEHIND_PER_WAR_OPERATIONS', 'OP_DEFENSE', 1),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_MILITARY_ENGINEERING', 3),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_METAL_CASTING', 3),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_MILITARY_SCIENCE', 4),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_COMBUSTION', 4),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_COMBINED_ARMS', 4),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_ADVANCED_FLIGHT', 3),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_STEALTH_TECHNOLOGY', 3),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_NUCLEAR_FISSION', 3),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_NUCLEAR_FUSION', 3),
  ('EC_AI_MILITARY_BEHIND_TECHS', 'TECH_ROBOTICS', 3),
  -- R90: RHAI's native default reserve is 3; use the same bounded value
  -- when the Lags Military recovery strategy is active so a weak AI funds
  -- replenishment before the emergency spend-down layers take over.
  ('EC_AI_MILITARY_BEHIND_SAVINGS', 'SAVING_UNITS', 3);

INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, StringVal)
VALUES
  ('EC_AI_MILITARY_BEHIND_CITY_EVENTS', 'CITY_EVENT_DEFAULT', 'Upgrade Units'),
  ('EC_AI_MILITARY_BEHIND_CITY_EVENTS', 'CITY_UNDER_THREAT', 'Upgrade Units');

-- Military civic path for an AI that is behind in military strength. These
-- are all native Civics.xml entries and are only a preference input for the
-- recovery strategy; they do not bypass civic prerequisites or costs.
INSERT OR IGNORE INTO AiFavoredItems (ListType, Item, Value)
VALUES
  ('EC_AI_MILITARY_BEHIND_CIVICS', 'CIVIC_MILITARY_TRADITION', 4),
  ('EC_AI_MILITARY_BEHIND_CIVICS', 'CIVIC_MILITARY_TRAINING', 4),
  ('EC_AI_MILITARY_BEHIND_CIVICS', 'CIVIC_DEFENSIVE_TACTICS', 4),
  ('EC_AI_MILITARY_BEHIND_CIVICS', 'CIVIC_MERCENARIES', 4),
  ('EC_AI_MILITARY_BEHIND_CIVICS', 'CIVIC_NATIONALISM', 4),
  ('EC_AI_MILITARY_BEHIND_CIVICS', 'CIVIC_SCORCHED_EARTH', 3),
  ('EC_AI_MILITARY_BEHIND_CIVICS', 'CIVIC_MOBILIZATION', 5),
  ('EC_AI_MILITARY_BEHIND_CIVICS', 'CIVIC_RAPID_DEPLOYMENT', 5);
