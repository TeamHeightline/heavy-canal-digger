local M = {}

local function water(surface, position)
  return surface.get_tile(position).prototype.collision_mask.layers.water_tile == true
end

-- Cleanup is limited to the anchors of tiles that really became water. Do not
-- erase bank vegetation while native tile correction is still in progress.
function M.clear_water(surface, tiles)
  local seen = {}
  for _, tile in ipairs(tiles) do
    local position = tile.position or tile
    local p = {x=math.floor(position.x or position[1]), y=math.floor(position.y or position[2])}
    local key = p.x .. ":" .. p.y
    if not seen[key] then
      seen[key] = true
      if water(surface, p) then
        surface.destroy_decoratives{position=p, exclude_soft=false}
      end
    end
  end
end

-- Repair the already excavated stretch visible near an existing machine on
-- upgrade. Search decoratives locally, then remove only water-anchored ones.
function M.clear_nearby(car)
  local p, radius = car.position, 32
  local decoratives = car.surface.find_decoratives_filtered{
    area={{p.x-radius,p.y-radius},{p.x+radius,p.y+radius}}, exclude_soft=false
  }
  local tiles = {}
  for _, decorative in pairs(decoratives) do tiles[#tiles+1] = decorative.position end
  M.clear_water(car.surface, tiles)
end

return M
