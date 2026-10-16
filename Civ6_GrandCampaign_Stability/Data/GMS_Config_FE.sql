-- Round 2: keep the reserve pool independently switchable in Advanced Options.
INSERT OR IGNORE INTO Parameters(
    ParameterId, Name, Description, Domain, DefaultValue,
    ConfigurationGroup, ConfigurationId, GroupId, SortIndex
) VALUES (
    'GMS_PANTHEON_FALLBACK',
    'LOC_GMS_PANTHEON_FALLBACK_NAME',
    'LOC_GMS_PANTHEON_FALLBACK_DESC',
    'bool', 1,
    'Game', 'GMS_PANTHEON_FALLBACK', 'AdvancedOptions', 1750
);

INSERT OR IGNORE INTO Parameters(
    ParameterId, Name, Description, Domain, DefaultValue,
    ConfigurationGroup, ConfigurationId, GroupId, SortIndex
) VALUES (
    'GMS_SATELLITE_SAFE_MODE',
    'LOC_GMS_SATELLITE_SAFE_MODE_NAME',
    'LOC_GMS_SATELLITE_SAFE_MODE_DESC',
    'bool', 0,
    'Game', 'GMS_SATELLITE_SAFE_MODE', 'AdvancedOptions', 1751
);

INSERT OR IGNORE INTO Parameters(
    ParameterId, Name, Description, Domain, DefaultValue,
    ConfigurationGroup, ConfigurationId, GroupId, SortIndex
) VALUES (
    'GMS_SATELLITE_CHUNKED_MODE',
    'LOC_GMS_SATELLITE_CHUNKED_MODE_NAME',
    'LOC_GMS_SATELLITE_CHUNKED_MODE_DESC',
    'bool', 0,
    'Game', 'GMS_SATELLITE_CHUNKED_MODE', 'AdvancedOptions', 1754
);

INSERT OR IGNORE INTO Parameters(
    ParameterId, Name, Description, Domain, DefaultValue,
    ConfigurationGroup, ConfigurationId, GroupId, SortIndex
) VALUES (
    'GMS_SATELLITE_CHUNK_SIZE',
    'LOC_GMS_SATELLITE_CHUNK_SIZE_NAME',
    'LOC_GMS_SATELLITE_CHUNK_SIZE_DESC',
    'uint', 500,
    'Game', 'GMS_SATELLITE_CHUNK_SIZE', 'AdvancedOptions', 1755
);

INSERT OR IGNORE INTO Parameters(
    ParameterId, Name, Description, Domain, DefaultValue,
    ConfigurationGroup, ConfigurationId, GroupId, SortIndex
) VALUES (
    'GMS_NATURAL_WONDER_SAFE_MODE',
    'LOC_GMS_NATURAL_WONDER_SAFE_MODE_NAME',
    'LOC_GMS_NATURAL_WONDER_SAFE_MODE_DESC',
    'bool', 0,
    'Game', 'GMS_NATURAL_WONDER_SAFE_MODE', 'AdvancedOptions', 1752
);

INSERT OR IGNORE INTO Parameters(
    ParameterId, Name, Description, Domain, DefaultValue,
    ConfigurationGroup, ConfigurationId, GroupId, SortIndex
) VALUES (
    'GMS_DEBUG_TIMING',
    'LOC_GMS_DEBUG_TIMING_NAME',
    'LOC_GMS_DEBUG_TIMING_DESC',
    'bool', 0,
    'Game', 'GMS_DEBUG_TIMING', 'AdvancedOptions', 1753
);

INSERT OR IGNORE INTO Parameters(
    ParameterId, Name, Description, Domain, DefaultValue,
    ConfigurationGroup, ConfigurationId, GroupId, SortIndex
) VALUES (
    'GMS_CLIMATE_DIAGNOSTICS',
    'LOC_GMS_CLIMATE_DIAGNOSTICS_NAME',
    'LOC_GMS_CLIMATE_DIAGNOSTICS_DESC',
    'bool', 0,
    'Game', 'GMS_CLIMATE_DIAGNOSTICS', 'AdvancedOptions', 1756
);

INSERT OR IGNORE INTO Parameters(
    ParameterId, Name, Description, Domain, DefaultValue,
    ConfigurationGroup, ConfigurationId, GroupId, SortIndex
) VALUES (
    'GMS_SNAPSHOT_OBJECT_BUDGET',
    'LOC_GMS_SNAPSHOT_OBJECT_BUDGET_NAME',
    'LOC_GMS_SNAPSHOT_OBJECT_BUDGET_DESC',
    'uint', 10000,
    'Game', 'GMS_SNAPSHOT_OBJECT_BUDGET', 'AdvancedOptions', 1757
);

