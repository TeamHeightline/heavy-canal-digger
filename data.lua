local name = "heavy-canal-digger"
local root = "__" .. name .. "__/"
local car = table.deepcopy(data.raw.car.car)
car.name = name
car.icon = root .. "graphics/icon.png"
car.icon_size = 128
car.minable = {mining_time = 1, result = name}
car.max_health = 2500
car.collision_box = {{-1.35, -2.0}, {1.35, 2.0}}
car.selection_box = {{-1.6, -5.6}, {1.6, 3.4}}
car.drawing_box_vertical_extension = 5
car.weight = 16000
car.consumption = "600kW"
car.effectivity = 1
car.braking_power = "2400kW"
car.friction = 0.006
car.rotation_speed = 0.0025
car.rotation_snap_angle = 0.005
car.tank_driving = true
car.has_belt_immunity = true
-- All water, including excavated channels, blocks this land vehicle.
car.collision_mask=table.deepcopy(require("collision-mask-util").get_mask(car))
car.collision_mask.layers.water_tile=true
car.collision_mask.layers.player=nil
car.collision_mask.layers.out_of_map=true
if data.raw["collision-layer"]["lava_tile"] then car.collision_mask.layers.lava_tile=true end
car.inventory_size = 80
car.trash_inventory_size = 0
car.auto_sort_inventory = false
-- Native vehicle acceleration, braking, traction and collision damage.
car.energy_per_hit_point = 1
car.resistances = {{type="fire",percent=50},{type="impact",percent=20},{type="acid",percent=20}}
car.immune_to_tree_impacts = false
car.immune_to_rock_impacts = false
car.energy_source = {type = "burner", fuel_categories = {"chemical"}, effectivity = 1, fuel_inventory_size = 3}
car.guns = nil
car.turret_animation = nil
car.light_animation = nil
car.track_particle_triggers = nil
car.corpse = nil
-- Native sprites are visible under the placement cursor and in entity ghosts.
car.animation = require("graphics.native-animation")
car.localised_name = {"entity-name." .. name}
car.localised_description = {"entity-description." .. name}
local working = table.deepcopy(car)
working.name = name .. "-working"
working.animation = require("graphics.native-work-animation")
working.rotation_speed = 0.0005
-- Bank-side excavation must not snap the chassis into the nearby water.
working.rotation_snap_angle = 0
working.hidden = true
working.placeable_by = {item=name, count=1}
working.factoriopedia_alternative = name

data:extend({car, working,
  {type = "item-with-entity-data", name = name, icon = car.icon, icon_size = 128,
    subgroup = "transport", order = "b[personal-transport]-c[canal-digger]", place_result = name, stack_size = 1},
  {type = "recipe", name = name, enabled = false, energy_required = 30,
    ingredients = {
      {type="item",name="steel-plate",amount=100},
      {type="item",name="iron-gear-wheel",amount=80},
      {type="item",name="engine-unit",amount=20},
      {type="item",name="electronic-circuit",amount=40},
      {type="item",name="iron-plate",amount=100}
    },
    results = {{type="item",name=name,amount=1}}},
  {type="item",name=name.."-soil",
    icons={{icon="__base__/graphics/icons/landfill.png",icon_size=64,tint={r=0.66,g=0.46,b=0.26,a=1}}},
    subgroup="raw-material",order="z[soil]",stack_size=200,weight=1000},
  {type="recipe",name=name.."-landfill",enabled=false,energy_required=0.5,
    ingredients={{type="item",name=name.."-soil",amount=20}},
    results={{type="item",name="landfill",amount=1}},
    allow_productivity=false,auto_recycle=false},
})

-- The machine is available at precisely the locomotive's research tier.
local railway=data.raw.technology.railway
railway.effects=railway.effects or {}
for _,recipe in ipairs{name,name.."-landfill"} do
  railway.effects[#railway.effects+1]={type="unlock-recipe",recipe=recipe}
end

data:extend({{type="custom-input",name=name.."-rotate",key_sequence="",
  linked_game_control="rotate",consuming="none"}})
