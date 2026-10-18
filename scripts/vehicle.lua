local config = require("machine-config")
local work_model = require("scripts.work-model")
local decoratives = require("scripts.decoratives")
local M = {name = config.name}
local acceleration = defines.riding.acceleration
local soil = config.soil_item
local epsilon = 0.000001

local function pose(car)
  return {x=car.position.x, y=car.position.y, orientation=car.orientation, surface=car.surface.index,tick=game.tick}
end

local function forward(orientation)
  local angle=orientation*2*math.pi
  return math.sin(angle), -math.cos(angle)
end

local function head_position(p)
  -- This is the same inverse 45-degree projection used by the native sprites.
  local angle=p.orientation*2*math.pi
  local heading=math.atan2(math.sin(angle),math.cos(angle)*math.sqrt(2))
  return {x=p.x+math.sin(heading)*config.head_offset,
    y=p.y-math.cos(heading)*config.head_offset/math.sqrt(2)}
end

local function tile_key(p) return p.x..":"..p.y end
local function reset_work(state)
  state.pending={};state.queued={};state.job=nil;state.progress=0;state.total=1
end
function M.new_state(car)
  return {entity=car,enabled=false,progress=0,total=1,status="off",pending={},queued={},
    last_pose=pose(car),head_position=head_position(pose(car)),soil_collected=0}
end
function M.toggle(state,enabled)
  state.enabled=enabled;state.status=enabled and "ready" or "off"
  reset_work(state)
  if state.entity and state.entity.valid then state.last_pose=pose(state.entity) end
end
local function stop(car,state,status)
  car.speed=0;car.effectivity_modifier=0;car.consumption_modifier=0;state.status=status
end
local function clearance(car,state)
  -- Tool clearance must never disable the native longitudinal escape controls.
  state.blocked_by_chassis=true;state.status="clearance"
end
local function is_water(tile) return tile.prototype.collision_mask.layers.water_tile==true end
local function unsafe_ground(tile)
  local layers=tile.prototype.collision_mask.layers
  return is_water(tile) or layers.lava_tile or layers.empty_space or layers.out_of_map
    or tile.name=="out-of-map" or tile.name=="empty-space"
end
local function can_excavate_surface(surface)
  return surface.name=="nauvis" or (surface.planet and surface.planet.name=="nauvis")
end
local ignored_types={resource=true,["item-entity"]=true,["entity-ghost"]=true,["tile-ghost"]=true,
  corpse=true,["rail-remnants"]=true,["construction-robot"]=true,["logistic-robot"]=true,
  ["combat-robot"]=true,["deconstructible-tile-proxy"]=true,["item-request-proxy"]=true,
  ["highlight-box"]=true,["flying-text"]=true,projectile=true,["artillery-projectile"]=true,
  stream=true,explosion=true,fire=true,smoke=true,["smoke-with-trigger"]=true,["particle-source"]=true}
local function character(occupant)
  if occupant and occupant.object_name=="LuaPlayer" then return occupant.character end
  return occupant
end
local function box_shape(box)
  local angle=(box.orientation or 0)*2*math.pi
  return {x=(box.left_top.x+box.right_bottom.x)/2,y=(box.left_top.y+box.right_bottom.y)/2,
    hx=(box.right_bottom.x-box.left_top.x)/2,hy=(box.right_bottom.y-box.left_top.y)/2,
    ux=math.cos(angle),uy=math.sin(angle),vx=-math.sin(angle),vy=math.cos(angle)}
end
local function chassis_shape(car,p)
  -- LuaEntity.bounding_box may be expanded for entity queries. The actual
  -- chassis is the prototype rectangle rotated about the vehicle's position.
  local box=car.prototype.collision_box
  local angle=p.orientation*2*math.pi
  local cx=(box.left_top.x+box.right_bottom.x)/2
  local cy=(box.left_top.y+box.right_bottom.y)/2
  local result=box_shape(box)
  result.x=p.x+math.cos(angle)*cx-math.sin(angle)*cy
  result.y=p.y+math.sin(angle)*cx+math.cos(angle)*cy
  angle=angle+(box.orientation or 0)*2*math.pi
  result.ux=math.cos(angle);result.uy=math.sin(angle)
  result.vx=-math.sin(angle);result.vy=math.cos(angle)
  return result
end
local function box_radius(b,x,y)
  return b.hx*math.abs(b.ux*x+b.uy*y)+b.hy*math.abs(b.vx*x+b.vy*y)
end
local function boxes_overlap(a,b)
  local dx,dy=b.x-a.x,b.y-a.y
  for _,axis in ipairs({{a.ux,a.uy},{a.vx,a.vy},{b.ux,b.uy},{b.vx,b.vy}}) do
    local x,y=axis[1],axis[2]
    if math.abs(dx*x+dy*y)>=box_radius(a,x,y)+box_radius(b,x,y)-epsilon then return false end
  end
  return true
end
local function box_intersects_tile(box,p)
  return boxes_overlap(box,{x=p.x+.5,y=p.y+.5,hx=.5,hy=.5,ux=1,uy=0,vx=0,vy=1})
end
local function box_area(box)
  local hx,hy=box_radius(box,1,0),box_radius(box,0,1)
  return {{box.x-hx,box.y-hy},{box.x+hx,box.y+hy}}
end
local function grounded(surface,box)
  local area=box_area(box)
  for x=math.floor(area[1][1]+epsilon),math.floor(area[2][1]-epsilon) do
    for y=math.floor(area[1][2]+epsilon),math.floor(area[2][2]-epsilon) do
      if box_intersects_tile(box,{x=x,y=y}) and unsafe_ground(surface.get_tile(x,y)) then return false end
    end
  end
  return true
end
local function chassis_clear(car,p)
  local box=chassis_shape(car,p)
  if not grounded(car.surface,box) then return false end
  local driver,passenger=character(car.get_driver()),character(car.get_passenger())
  for _,entity in pairs(car.surface.find_entities_filtered({area=box_area(box)})) do
    if entity~=car and entity~=driver and entity~=passenger and not ignored_types[entity.type]
      and boxes_overlap(box,box_shape(entity.bounding_box)) then return false end
  end
  return true
end
function M.can_rotate(car,orientation)
  local p=pose(car);p.orientation=orientation
  return chassis_clear(car,p)
end
local function keep_on_land(car,state,current,previous)
  if grounded(car.surface,chassis_shape(car,current)) then
    state.initial_ground_checked=true;return current
  end
  -- A rejected native turn is undone at the SAME position. Validate before
  -- writing orientation; no auxiliary turn clamp can push a corner into water.
  local dry=state.last_dry_pose or previous
  if dry and dry.surface==current.surface and dry.tick and game.tick-dry.tick<=1 then
    local old_heading={x=current.x,y=current.y,orientation=dry.orientation,surface=current.surface,tick=game.tick}
    if chassis_clear(car,old_heading) then
      car.orientation=old_heading.orientation;state.turn_rejected=true
      state.initial_ground_checked=true;return pose(car)
    end
    local dx,dy=current.x-dry.x,current.y-dry.y
    if dx*dx+dy*dy<=config.max_dry_rollback^2
      and chassis_clear(car,dry) and car.teleport({dry.x,dry.y}) then
      car.orientation=dry.orientation;car.speed=0;state.turn_rejected=true
      state.initial_ground_checked=true;return pose(car)
    end
  end
  -- One-time repair for a legacy save whose last tick was already stranded by
  -- a tiny turn. Search only headings within 3.6 degrees at this exact position.
  -- A machine surrounded by water has no valid candidate and remains stopped.
  if not state.initial_ground_checked then
    state.initial_ground_checked=true
    for step=1,config.legacy_turn_recovery_steps do
      for _,sign in ipairs({-1,1}) do
        local candidate={x=current.x,y=current.y,surface=current.surface,tick=game.tick,
          orientation=(current.orientation+sign*step*config.work_rotation_speed)%1}
        if chassis_clear(car,candidate) then
          car.orientation=candidate.orientation;car.speed=0;state.turn_rejected=true
          return pose(car)
        end
      end
    end
  end
end
local function check_tile(car,p,chassis)
  local tile=car.surface.get_tile(p)
  if is_water(tile) then return "water",tile end
  if unsafe_ground(tile) then return "terrain",tile end
  if box_intersects_tile(chassis,p) then return "clearance",tile end
  local driver,passenger=character(car.get_driver()),character(car.get_passenger())
  -- No object-layer filter: rails, belts, plants and modded buildings can use
  -- completely different masks. All real occupied tiles remain intact.
  local area={{p.x+epsilon,p.y+epsilon},{p.x+1-epsilon,p.y+1-epsilon}}
  for _,entity in pairs(car.surface.find_entities_filtered({area=area})) do
    if entity~=car and entity~=driver and entity~=passenger and not ignored_types[entity.type]
      and box_intersects_tile(box_shape(entity.bounding_box),p) then return "blocked",tile end
  end
  return "land",tile
end

local function cross(a,b,c) return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) end
local function hull(points)
  table.sort(points,function(a,b) return a.x==b.x and a.y<b.y or a.x<b.x end)
  local lower,upper={},{}
  for i=1,#points do
    while #lower>=2 and cross(lower[#lower-1],lower[#lower],points[i])<=0 do table.remove(lower) end
    lower[#lower+1]=points[i]
  end
  for i=#points,1,-1 do
    while #upper>=2 and cross(upper[#upper-1],upper[#upper],points[i])<=0 do table.remove(upper) end
    upper[#upper+1]=points[i]
  end
  table.remove(lower);table.remove(upper)
  for _,p in ipairs(upper) do lower[#lower+1]=p end
  return lower
end
local function strip_corners(p,points)
  local centre=head_position(p)
  local fx,fy=forward(p.orientation);local rx,ry=-fy,fx
  for _,along in ipairs({-config.channel_depth/2,config.channel_depth/2}) do
    for _,side in ipairs({-config.channel_width/2,config.channel_width/2}) do
      points[#points+1]={x=centre.x+fx*along+rx*side,y=centre.y+fy*along+ry*side}
    end
  end
end
local function polygon_intersects_tile(poly,x,y)
  -- SAT for convex swept strip versus the tile square. The surrounding loop
  -- already tests the square's two world-aligned axes.
  for i=1,#poly do
    local a,b=poly[i],poly[i%#poly+1]
    local nx,ny=-(b.y-a.y),b.x-a.x
    local low,high
    for _,p in ipairs(poly) do
      local value=p.x*nx+p.y*ny
      low=not low and value or math.min(low,value);high=not high and value or math.max(high,value)
    end
    local centre=(x+.5)*nx+(y+.5)*ny
    local radius=(math.abs(nx)+math.abs(ny))/2
    if centre+radius<=low+epsilon or centre-radius>=high-epsilon then return false end
  end
  return true
end
local function swept_tiles(previous,current)
  local points={};strip_corners(previous,points);strip_corners(current,points)
  local poly=hull(points)
  local minx,maxx,miny,maxy=poly[1].x,poly[1].x,poly[1].y,poly[1].y
  for _,p in ipairs(poly) do minx=math.min(minx,p.x);maxx=math.max(maxx,p.x);miny=math.min(miny,p.y);maxy=math.max(maxy,p.y) end
  local result={}
  for x=math.floor(minx+epsilon),math.floor(maxx-epsilon) do
    for y=math.floor(miny+epsilon),math.floor(maxy-epsilon) do
      if polygon_intersects_tile(poly,x,y) then result[#result+1]={x=x,y=y} end
    end
  end
  return result
end
local function load_fuel(burner)
  local old = burner.currently_burning
  if old then
    local burnt = old.name.burnt_result
    if burnt then
      local result = burner.burnt_result_inventory
      if not result or not result.valid or result.get_insertable_count({name = burnt.name, quality = old.quality.name}) < 1 then return false end
      result.insert({name = burnt.name, count = 1, quality = old.quality.name})
    end
    -- Setting this to nil does not create burnt products; handled above once.
    burner.currently_burning = nil
  end
  for i = 1, #burner.inventory do
    local stack = burner.inventory[i]
    if stack.valid_for_read and stack.prototype.fuel_value > 0
      and burner.fuel_categories[stack.prototype.fuel_category] then
      local name, quality, energy = stack.name, stack.quality.name, stack.prototype.fuel_value
      stack.count = stack.count - 1
      burner.currently_burning = {name = name, quality = quality}
      burner.remaining_burning_fuel = energy
      return true
    end
  end
  return false
end

local function debit(car, amount)
  local burner = car.burner
  if not burner then return 0 end
  local paid = 0
  while paid + epsilon < amount do
    if burner.remaining_burning_fuel <= epsilon and not load_fuel(burner) then break end
    local used = math.min(amount - paid, burner.remaining_burning_fuel)
    burner.remaining_burning_fuel = burner.remaining_burning_fuel - used
    paid = paid + used
  end
  return paid
end

local function terrain_work(entries,car)
  local tiles={}
  for _,entry in ipairs(entries) do tiles[#tiles+1]={position=entry.position} end
  return work_model.terrain(tiles,car.surface,config.kind)/config.work_parallelism
end
local function prepare_job(car,state,chassis)
  local pool={}
  if state.job then
    local job=state.job
    local old_fraction=job.total>0 and math.min(1,job.progress/job.total) or 0
    for _,entry in ipairs(job.entries) do
      -- Convert the old batch's shared payment into per-cell credit once.
      entry.cost=entry.cost or terrain_work({entry},car)
      if entry.credit==nil then entry.credit=entry.cost*old_fraction end
      pool[#pool+1]=entry
    end
  end
  for _,entry in ipairs(state.pending) do pool[#pool+1]=entry end
  local entries,pending,total,paid={},{},0,0
  local deferred,ready_count=nil,0
  local head=state.head_position
  for _,entry in ipairs(pool) do
    local p=entry.position
    local dx,dy=p.x+.5-head.x,p.y+.5-head.y
    local kind,tile=check_tile(car,p,chassis)
    if dx*dx+dy*dy>config.deferred_radius^2 or kind=="water" or kind=="terrain" then
      -- Do not excavate an abandoned work site far behind the current head.
      -- Discarded work produces neither water nor soil.
      state.queued[entry.key]=nil
    else
      local cost=terrain_work({entry},car)
      local credit=entry.tile==tile.name and math.min(cost,entry.credit or 0) or 0
      local next_entry={key=entry.key,position=p,tile=tile.name,cost=cost,credit=credit}
      if kind=="land" and #entries<config.max_batch_tiles then
        entries[#entries+1]=next_entry;total=total+cost;paid=paid+credit
      else
        pending[#pending+1]=next_entry
        if kind=="land" then ready_count=ready_count+1
        elseif kind=="clearance" then deferred=deferred or "clearance"
        else deferred="blocked" end
      end
    end
  end
  state.pending=pending
  state.ready_pending_count=ready_count
  state.job=#entries>0 and {entries=entries,progress=paid,total=total} or nil
  state.progress=paid;state.total=total>0 and total or 1
  return deferred
end
local function credit_work(job,amount)
  local remaining=job.total-job.progress
  local fraction=remaining>0 and math.min(1,amount/remaining) or 0
  for _,entry in ipairs(job.entries) do
    entry.credit=entry.credit+(entry.cost-entry.credit)*fraction
  end
  job.progress=math.min(job.total,job.progress+amount)
end
local function commit_job(car,state)
  local job=state.job
  local tiles,paid_keys={},{}
  for _,entry in ipairs(job.entries) do
    tiles[#tiles+1]={name="water",position=entry.position};paid_keys[entry.key]=true
  end
  local trunk=car.get_inventory(defines.inventory.car_trunk)
  if trunk.get_insertable_count(soil)<#tiles then return false,"cargo" end
  -- Native correction makes normal water edges. Snapshot its local edge band
  -- so correction cannot leave unbilled neighbouring land or buildings flooded.
  local neighbours={}
  for _,entry in ipairs(job.entries) do
    local p=entry.position
    for x=p.x-2,p.x+2 do for y=p.y-2,p.y+2 do
      local q={x=x,y=y};local key=tile_key(q)
      if not paid_keys[key] and not neighbours[key] then
        local tile=car.surface.get_tile(q)
        neighbours[key]={name=tile.name,position=q,hidden=tile.hidden_tile,double_hidden=tile.double_hidden_tile}
      end
    end end
  end
  -- This changes real map tiles, exactly the reverse of placing landfill.
  -- abort_on_collision never destroys a tree, rock, building or vehicle.
  car.surface.set_tiles(tiles,true,"abort_on_collision",false,false)
  local retry={}
  for _,tile in ipairs(tiles) do if not is_water(car.surface.get_tile(tile.position)) then retry[#retry+1]=tile end end
  if #retry>0 then car.surface.set_tiles(retry,false,"abort_on_collision",false,false) end
  local restore={}
  for _,old in pairs(neighbours) do
    if car.surface.get_tile(old.position).name~=old.name then restore[#restore+1]={name=old.name,position=old.position} end
  end
  if #restore>0 then
    car.surface.set_tiles(restore,false,false,false,false)
    for _,old in pairs(neighbours) do
      car.surface.set_hidden_tile(old.position,old.hidden)
      car.surface.set_double_hidden_tile(old.position,old.double_hidden)
    end
  end
  local converted,remaining={},{ }
  for _,entry in ipairs(job.entries) do
    if is_water(car.surface.get_tile(entry.position)) then
      converted[#converted+1]={name="water",position=entry.position};state.queued[entry.key]=nil
    else remaining[#remaining+1]=entry end
  end
  if #converted>0 then
    -- No external event runs between the capacity check and this insertion.
    trunk.insert({name=soil,count=#converted})
    state.soil_collected=state.soil_collected+#converted
  end
  if #remaining>0 then
    job.entries=remaining;job.total=terrain_work(remaining,car);job.progress=job.total
    state.progress,state.total=job.progress,job.total
  else state.job=nil;state.progress=0;state.total=1 end
  if #converted>0 then
    script.raise_script_set_tiles({surface_index=car.surface.index,tiles=converted})
    decoratives.clear_water(car.surface,converted)
  end
  return #remaining==0,#remaining>0 and "blocked" or nil
end

function M.update(car,state)
  -- Native prototypes own acceleration, braking and both angular speed limits.
  -- Never force a second, unchecked orientation after native collision handling.
  car.effectivity_modifier=1;car.consumption_modifier=1
  state.blocked_by_chassis=false;state.turn_rejected=false
  local previous=state.last_pose or pose(car)
  local current=pose(car)
  local dx,dy=current.x-previous.x,current.y-previous.y
  local teleported=current.surface~=previous.surface or dx*dx+dy*dy>4
  if teleported then
    reset_work(state);state.last_dry_pose=nil;state.initial_ground_checked=nil;previous=current
  end
  current=keep_on_land(car,state,current,previous)
  if not current then
    state.last_pose=pose(car);state.head_position=head_position(state.last_pose)
    stop(car,state,"terrain");return
  end
  local limit=state.enabled and config.work_speed or config.travel_speed
  if math.abs(car.speed)>limit then car.speed=car.speed<0 and -limit or limit end
  state.head_position=head_position(current);state.last_pose=current;state.last_dry_pose=current
  state.pending=state.pending or {};state.queued=state.queued or {};state.soil_collected=state.soil_collected or 0
  local chassis=chassis_shape(car,current)
  if not state.enabled then state.status="off";return end
  if not car.get_driver() then state.status="idle";return end
  local input=car.riding_state.acceleration
  local driving=math.abs(car.speed)>epsilon or input==acceleration.accelerating or input==acceleration.reversing
  if not driving then state.status="ready";return end
  if not can_excavate_surface(car.surface) then state.status="surface";return end

  local candidates=swept_tiles(previous,current)
  if game.tick%15==0 then decoratives.clear_water(car.surface,candidates) end
  local terrain_blocked=false
  for _,p in ipairs(candidates) do
    local key=tile_key(p)
    local kind,tile=check_tile(car,p,chassis)
    if (kind=="land" or kind=="clearance" or kind=="blocked") and not state.queued[key] then
      state.pending[#state.pending+1]={key=key,position=p,tile=tile.name};state.queued[key]=true
    elseif kind=="terrain" then terrain_blocked=true end
  end
  local deferred=prepare_job(car,state,chassis)
  if not state.job then
    if deferred=="clearance" then clearance(car,state)
    else state.status=deferred or (terrain_blocked and "terrain" or "ready") end
    return
  end
  local job=state.job
  local trunk=car.get_inventory(defines.inventory.car_trunk)
  if not trunk or trunk.get_insertable_count(soil)<#job.entries then state.status="cargo";return end
  if job.progress+epsilon<job.total then
    local full_tick_energy=config.tool_power/60
    local requested=math.min(1,job.total-job.progress)*full_tick_energy
    local paid=debit(car,requested)
    if paid<=epsilon then state.status="fuel";return end
    credit_work(job,paid/full_tick_energy)
    state.progress,state.total,state.status=job.progress,job.total,"working"
    -- Pause only while the tool is actually catching up. A full trunk, empty
    -- burner or deferred cell must leave native escape controls available.
    if state.ready_pending_count+#job.entries>config.max_pending_tiles then car.speed=0 end
  else state.status="working" end
  if job.progress+epsilon>=job.total then
    local ok,reason=commit_job(car,state)
    if not ok then state.status=reason end
  end
end
return M
