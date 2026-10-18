-- Native graphics require separate car prototypes. Replace only after every
-- inventory and occupant has safely reached the new car; never recreate items.
local config = require("machine-config")
local M = {}

local function id(value)
  return type(value) == "string" and value or value.name
end

local function occupant_entity(value)
  if value and value.object_name == "LuaPlayer" then return value.character or value end
  return value
end

local function same_occupant(left, right)
  return occupant_entity(left) == occupant_entity(right)
end

local function snapshot(car)
  local riding = car.riding_state
  local result = {
    position = {x = car.position.x, y = car.position.y},
    orientation = car.orientation, speed = car.speed,
    riding = {acceleration = riding.acceleration, direction = riding.direction},
    driver = car.get_driver(), passenger = car.get_passenger(),
    health = car.health, color = car.color, last_user = car.last_user,
    destructible = car.destructible, operable = car.operable,
    minable_flag = car.minable_flag, rotatable = car.rotatable,
    disabled_by_script = car.disabled_by_script,
    enable_logistics_while_moving = car.enable_logistics_while_moving,
    driver_is_gunner = car.driver_is_gunner,
    selected_gun_index = car.selected_gun_index,
    consumption_modifier = car.consumption_modifier,
    effectivity_modifier = car.effectivity_modifier,
    friction_modifier = car.friction_modifier
  }
  local burner = car.burner
  if burner then
    local burning = burner.currently_burning
    result.burner = {
      burning = burning and {name = id(burning.name), quality = id(burning.quality)},
      remaining = burner.remaining_burning_fuel, heat = burner.heat
    }
  end
  -- LuaEntity.tags belongs to entity ghosts. Real cars have no entity tags;
  -- tagged items inside their inventories are preserved by swap_stack below.
  return result
end

local function prepare_inventory(source, target, label, result)
  if not source and not target then return end
  assert(source and source.valid and target and target.valid, label .. " inventory is unavailable")
  assert(#source == #target, label .. " inventory size differs")
  assert(target.is_empty(), label .. " replacement inventory is not empty")
  local entry = {source = source, target = target, filters = {}}
  if source.supports_filters() then
    assert(target.supports_filters(), label .. " replacement cannot preserve filters")
    entry.has_filters = true
    for index = 1, #source do entry.filters[index] = source.get_filter(index) end
  end
  if source.supports_bar() then
    assert(target.supports_bar(), label .. " replacement cannot preserve the inventory bar")
    entry.bar = source.get_bar()
  end
  -- A fresh native car has no inventory contents; remove only its defaults.
  if target.supports_bar() then target.set_bar() end
  if target.supports_filters() then
    for index = 1, #target do assert(target.set_filter(index, nil), label .. " filter cannot be cleared") end
  end
  result[#result + 1] = entry
end

local function prepare_inventories(old, replacement)
  local result = {}
  for _, spec in ipairs({
    {defines.inventory.car_trunk, "trunk"},
    {defines.inventory.car_ammo, "ammunition"},
    {defines.inventory.car_trash, "trash"}
  }) do
    prepare_inventory(old.get_inventory(spec[1]), replacement.get_inventory(spec[1]), spec[2], result)
  end
  prepare_inventory(old.get_fuel_inventory(), replacement.get_fuel_inventory(), "fuel", result)
  local old_burner, new_burner = old.burner, replacement.burner
  assert((old_burner ~= nil) == (new_burner ~= nil), "Replacement burner differs")
  if old_burner then
    prepare_inventory(old_burner.burnt_result_inventory, new_burner.burnt_result_inventory, "burnt result", result)
  end
  return result
end

local function copy_properties(car, saved)
  car.orientation = saved.orientation
  car.health = saved.health
  if saved.color then car.color = saved.color end
  if saved.last_user then car.last_user = saved.last_user end
  for _, key in ipairs({"destructible", "operable", "minable_flag", "rotatable", "disabled_by_script",
    "enable_logistics_while_moving", "driver_is_gunner", "consumption_modifier", "effectivity_modifier", "friction_modifier"}) do
    if saved[key] ~= nil then car[key] = saved[key] end
  end
  if saved.selected_gun_index and saved.selected_gun_index > 0 then car.selected_gun_index = saved.selected_gun_index end
  if saved.burner then
    car.burner.currently_burning = saved.burner.burning
    car.burner.remaining_burning_fuel = saved.burner.remaining
    car.burner.heat = saved.burner.heat
  end
end

local function restore_motion(car, saved)
  car.orientation = saved.orientation
  car.riding_state = saved.riding
  car.speed = saved.speed
end

local function rollback(old, replacement, saved, inventories, moved)
  -- All affected inventories have stable slots: both prototypes deliberately
  -- disable auto_sort_inventory. Undo each full-data stack swap in reverse.
  for _, entry in ipairs(inventories) do
    if entry.target.supports_filters() then
      for index = 1, #entry.target do entry.target.set_filter(index, nil) end
    end
  end
  for index = #moved, 1, -1 do
    local entry = moved[index]
    assert(entry.source.swap_stack(entry.target), "Cannot restore an item stack")
  end
  replacement.set_driver(nil)
  replacement.set_passenger(nil)
  if not same_occupant(old.get_driver(), saved.driver) then old.set_driver(saved.driver) end
  if not same_occupant(old.get_passenger(), saved.passenger) then old.set_passenger(saved.passenger) end
  assert(same_occupant(old.get_driver(), saved.driver), "Cannot restore the driver")
  assert(same_occupant(old.get_passenger(), saved.passenger), "Cannot restore the passenger")
  restore_motion(old, saved)
  assert(replacement.destroy({raise_destroy = false}), "Cannot remove the empty replacement")
end

-- Returns the replacement on success, or nil,error with the old car retained.
-- Storage keys, enabled state and player GUI references are managed by control.
function M.replace(state, enabled)
  local old = state and state.entity
  if not old or not old.valid or type(enabled) ~= "boolean" then return nil, "invalid-mode-switch" end
  if state.mode_switch_recovery and state.mode_switch_recovery.valid then return nil, "mode-switch-recovery-pending" end
  local wanted = enabled and (config.name .. "-working") or config.name
  if old.name == wanted then return old end
  if old.type ~= "car" or (old.name ~= config.name and old.name ~= config.name .. "-working") then
    return nil, "invalid-mode-switch-entity"
  end
  -- These prototypes have no equipment grid. If another mod adds populated
  -- grids, fail without replacing the car rather than discard charged equipment.
  if old.grid and #old.grid.equipment > 0 then return nil, "mode-switch-equipment-grid" end
  local replacement, saved
  local inventories, moved = {}, {}
  local ok, failure = pcall(function()
    saved = snapshot(old)
    replacement = old.surface.create_entity({
      name = wanted, position = saved.position, orientation = saved.orientation,
      force = old.force, quality = old.quality.name, raise_built = false,
      snap_to_grid = false, move_stuck_players = false,
      create_build_effect_smoke = false, preserve_ghosts_and_corpses = true
    })
    assert(replacement and replacement.valid, "mode-switch-creation-failed")
    inventories = prepare_inventories(old, replacement)
    copy_properties(replacement, saved)
    for _, entry in ipairs(inventories) do
      for index = 1, #entry.source do
        local source, target = entry.source[index], entry.target[index]
        if source.valid_for_read then
          assert(target.swap_stack(source), "mode-switch-inventory-transfer-failed")
          moved[#moved + 1] = {source = source, target = target}
        end
      end
      if entry.has_filters then
        for index = 1, #entry.source do
          assert(entry.target.set_filter(index, entry.filters[index]), "mode-switch-filter-transfer-failed")
        end
      end
      if entry.bar then entry.target.set_bar(entry.bar) end
      assert(entry.source.is_empty(), "mode-switch-source-inventory-not-empty")
    end
    old.set_driver(nil)
    old.set_passenger(nil)
    replacement.set_driver(saved.driver)
    replacement.set_passenger(saved.passenger)
    assert(same_occupant(replacement.get_driver(), saved.driver), "mode-switch-driver-transfer-failed")
    assert(same_occupant(replacement.get_passenger(), saved.passenger), "mode-switch-passenger-transfer-failed")
    restore_motion(replacement, saved)
    -- This is the final, irreversible step. No item or player is left in old.
    assert(old.destroy({raise_destroy = false}), "mode-switch-old-entity-destroy-failed")
  end)
  if ok then
    state.entity = replacement
    return replacement
  end
  if replacement and replacement.valid then
    local restored, restore_error = pcall(rollback, old, replacement, saved, inventories, moved)
    if not restored then
      -- Never destroy a car that might still hold a full-data item stack.
      -- Keep a recoverable reference if an external mod invalidated a transfer.
      state.mode_switch_recovery = replacement
      log("Canal digger mode switch rollback requires recovery: " .. tostring(restore_error))
      return nil, "mode-switch-rollback-failed: " .. tostring(restore_error)
    end
  end
  return nil, tostring(failure)
end

return M
