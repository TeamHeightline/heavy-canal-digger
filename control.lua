local motion = require("scripts.motion-visuals")
local vehicle = require("scripts.vehicle")
local config = require("machine-config")
local mode_switch = require("scripts.mode-switch")
local decoratives = require("scripts.decoratives")
local frame_name = config.name .. "-panel"
local switch_name = config.name .. "-switch"
local show_panel

local function is_machine(car)
  return car and car.valid and (car.name == config.name or car.name == config.work_entity)
end

local function register(car)
  if not is_machine(car) then return end
  storage.machines = storage.machines or {}
  local state = storage.machines[car.unit_number]
  if not state then
    state = vehicle.new_state(car)
    vehicle.toggle(state, car.name == config.work_entity)
    storage.machines[car.unit_number] = state
  end
  return state
end

local function close(player)
  if not player then return end
  local frame = player.gui.relative[frame_name]
  if frame then frame.destroy() end
  if storage.opened then storage.opened[player.index] = nil end
end

local function scan()
  storage.machines = storage.machines or {}
  storage.opened = {}
  storage.rotation_requests = {}
  for _, player in pairs(game.players) do close(player) end
  for _, surface in pairs(game.surfaces) do
    for _, car in pairs(surface.find_entities_filtered{name={config.name,config.work_entity}}) do register(car) end
  end
end

local function change_mode(state, enabled)
  local old = state.entity
  local old_id = old.unit_number
  local viewers, selectors = {}, {}
  for _, player in pairs(game.players) do
    if player.opened == old then viewers[#viewers+1] = player end
    if player.selected == old then selectors[#selectors+1] = player end
  end
  storage.switching = true
  local replacement, err = mode_switch.replace(state, enabled)
  storage.switching = nil
  if not replacement then
    state.status = "switch-failed"
    log("Canal digger mode switch failed: " .. tostring(err))
    return false, err
  end
  motion.destroy(state)
  storage.machines[old_id] = nil
  storage.machines[replacement.unit_number] = state
  vehicle.toggle(state, enabled)
  for _, player in ipairs(selectors) do player.selected = replacement end
  for _, player in ipairs(viewers) do
    player.opened = replacement
    if show_panel then show_panel(player, replacement) end
  end
  return true
end

local function update_research()
  for _, force in pairs(game.forces) do
    local railway = force.technologies.railway
    for _, name in ipairs{config.name, config.name .. "-landfill"} do
      if force.recipes[name] and railway then force.recipes[name].enabled = railway.researched end
    end
  end
end

remote.add_interface(config.name, {
  set_tool_enabled = function(unit, enabled)
    local state = storage.machines and storage.machines[unit]
    if state and state.entity.valid and type(enabled) == "boolean" then
      return change_mode(state, enabled)
    end
    return false
  end,
  get_status = function(unit)
    local state = storage.machines and storage.machines[unit]
    if state and state.entity.valid then
      return {
        enabled=state.enabled, mode=state.enabled and "work" or "travel", status=state.status,
        progress=state.progress, total=state.total, soil_collected=state.soil_collected or 0,
        speed=state.entity.speed, head_position=state.head_position, unit_number=state.entity.unit_number
      }
    end
  end
})

script.on_init(function() scan(); update_research() end)
script.on_configuration_changed(function(event)
  scan()
  update_research()
  if event.mod_changes and event.mod_changes[config.name] then
    for id, state in pairs(storage.machines) do
      motion.destroy(state)
      if state.entity.valid then
        decoratives.clear_nearby(state.entity)
        local fresh = vehicle.new_state(state.entity)
        fresh.soil_collected = state.soil_collected or 0
        vehicle.toggle(fresh, state.entity.name == config.work_entity)
        storage.machines[id] = fresh
      else
        storage.machines[id] = nil
      end
    end
  end
end)
script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity,
  defines.events.script_raised_built, defines.events.script_raised_revive}, function(event)
  register(event.entity)
end)
script.on_event(defines.events.on_entity_cloned, function(event) register(event.destination) end)
script.on_event(defines.events.on_player_driving_changed_state, function(event)
  local player = game.get_player(event.player_index)
  if player then register(player.vehicle) end
end)

local function refresh(player, car)
  local frame = player.gui.relative[frame_name]
  local state = register(car)
  if not frame or not state then return end
  frame[switch_name].switch_state = state.enabled and "right" or "left"
  frame.work_progress.value = math.max(0, math.min(1, (state.progress or 0) / math.max(1, state.total or 1)))
  frame.work_progress.visible = state.status == "working" or (state.progress or 0) > 0
  frame.work_status.caption = {config.name .. ".status-" .. state.status}
  frame.soil_count.caption = {config.name .. ".soil-count", state.soil_collected or 0}
  frame.speed.caption = {config.name .. ".speed", string.format("%.1f", math.abs(car.speed) * 216)}
end

show_panel = function(player, car)
  close(player)
  if not is_machine(car) or car.force ~= player.force then return end
  register(car)
  storage.opened[player.index] = car
  local frame = player.gui.relative.add{
    type="frame", name=frame_name, caption={config.name .. ".tool"}, direction="vertical",
    anchor={gui=defines.relative_gui_type.car_gui, position=defines.relative_gui_position.left, name=car.name}
  }
  frame.style.maximal_width = 340
  frame.add{type="switch", name=switch_name, left_label_caption={config.name .. ".off"},
    right_label_caption={config.name .. ".on"}, switch_state="left"}
  frame.add{type="progressbar", name="work_progress", value=0}.style.width = 290
  frame.add{type="label", name="work_status", caption=""}.style.single_line = false
  frame.add{type="label", name="speed", caption=""}
  frame.add{type="label", name="soil_count", caption=""}
  local instructions = frame.add{type="label", caption={config.name .. ".instructions"}}
  instructions.style.single_line = false
  instructions.style.maximal_width = 300
  frame.add{type="label", caption={config.name .. ".power", config.tool_power / 1000000}}
  local channel = frame.add{type="label", caption={config.name .. ".channel-width", config.channel_width}}
  channel.style.single_line = false
  channel.style.maximal_width = 300
  refresh(player, car)
end
script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.get_player(event.player_index)
  if player and not storage.switching then show_panel(player, event.entity) end
end)
script.on_event(defines.events.on_gui_closed, function(event)
  if storage.switching then return end
  local player = game.get_player(event.player_index)
  local car = storage.opened[event.player_index]
  if player and car and car.valid and player.opened == car then return end
  close(player)
end)
script.on_event(defines.events.on_gui_switch_state_changed, function(event)
  if not event.element or not event.element.valid or event.element.name ~= switch_name then return end
  local player = game.get_player(event.player_index)
  local car = storage.opened[event.player_index]
  if player and car and car.valid and car.force == player.force and player.opened == car then
    local state = register(car)
    change_mode(state, event.element.switch_state == "right")
    refresh(player, state.entity)
  end
end)

script.on_event(defines.events.on_player_rotated_entity, function(event)
  local car = event.entity
  if not is_machine(car) then return end
  local state = register(car)
  local previous = state.last_pose
  if previous and previous.surface == car.surface.index
    and not vehicle.can_rotate(car, car.orientation)
    and vehicle.can_rotate(car, previous.orientation) then
    car.orientation = previous.orientation
  end
  state.native_rotation_tick = game.tick
  vehicle.toggle(state, state.enabled)
end)
script.on_event(config.name .. "-rotate", function(event)
  local player = game.get_player(event.player_index)
  if not player or player.vehicle or player.cursor_ghost
    or (player.cursor_stack and player.cursor_stack.valid_for_read) then return end
  local car = player.selected
  if not is_machine(car) or car.force ~= player.force or car.get_driver() or car.get_passenger() then return end
  storage.rotation_requests = storage.rotation_requests or {}
  storage.rotation_requests[event.player_index] = {entity=car, tick=game.tick}
end)

script.on_event(defines.events.on_tick, function(event)
  for index, request in pairs(storage.rotation_requests or {}) do
    if event.tick > request.tick then
      local car = request.entity
      if is_machine(car) and not car.get_driver() and not car.get_passenger() then
        local state = register(car)
        if (state.native_rotation_tick or -1) < request.tick then
          local orientation = (car.orientation + 0.25) % 1
          if vehicle.can_rotate(car, orientation) then
            car.orientation = orientation
            vehicle.toggle(state, state.enabled)
          end
        end
      end
      storage.rotation_requests[index] = nil
    end
  end
  for id, state in pairs(storage.machines) do
    if not state.entity.valid then
      motion.destroy(state)
      storage.machines[id] = nil
    else
      vehicle.update(state.entity, state)
    end
  end
  if event.tick % 15 == 0 then
    for index, car in pairs(storage.opened) do
      local player = game.get_player(index)
      if player and car.valid and player.opened == car then refresh(player, car)
      elseif player then close(player)
      else storage.opened[index] = nil end
    end
  end
end)
