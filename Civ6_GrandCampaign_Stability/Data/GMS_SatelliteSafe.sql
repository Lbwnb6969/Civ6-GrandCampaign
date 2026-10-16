-- Round 3: SAFE_OFF for Earth Satellite.
-- The project remains buildable and counts toward the science path;
-- only the one-shot full-map reveal is removed under the explicit setting.
DELETE FROM ProjectCompletionModifiers
WHERE ProjectType = 'PROJECT_LAUNCH_EARTH_SATELLITE'
  AND ModifierId = 'PROJECT_COMPLETION_EXPLORE_ENTIRE_MAP';

