return {
  name = "heavy-canal-digger",
  work_entity = "heavy-canal-digger-working",
  kind = "canal",
  soil_item = "heavy-canal-digger-soil",
  -- Additional power is charged only for actual excavation progress.
  tool_power = 1800000,
  -- Factorio speed is tiles/tick; multiply by 216 for kilometres/hour.
  travel_speed = 30 / 216,
  work_speed = 3 / 216,
  travel_rotation_speed = 0.0025,
  work_rotation_speed = 0.0005,
  -- Ground position of the lowered wheel in the orthographic model.
  head_offset = 4.3171458,
  -- A comfortable straight Cargo Ships corridor; tight bends need a basin.
  channel_width = 5.75,
  channel_depth = 0.1,
  -- Work is distributed across the width: one normal strip takes ~0.5 s.
  work_parallelism = 5.75,
  max_batch_tiles = 12,
  max_pending_tiles = 24,
  deferred_radius = 5,
  max_dry_rollback = 30 / 216 + 0.002,
  legacy_turn_recovery_steps = 20,
}
