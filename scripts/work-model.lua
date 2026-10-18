-- Work is charged PER entity, in simulation ticks at full tool power.
-- Random mine yields use their expected value for estimation; actual native
-- mining still decides the loot. No object is destroyed until its work is paid.
local M={}
function M.estimate(target)
  local prototype=target.prototype
  local mine=prototype.mineable_properties or {}
  local quantity=0
  for _,p in pairs(mine.products or {})do
    if p.type=="item" then
      quantity=quantity+((p.amount or ((p.amount_min or 0)+(p.amount_max or 0))/2)+(p.extra_count_fraction or 0))*(p.probability or 1)
    end
  end
  local max_health=target.max_health or 0
  local remaining=max_health>0 and math.max(0.15,math.min(1,(target.health or max_health)/max_health)) or 1
  local mining_time=mine.mining_time or 0
  local seconds
  if target.type=="cliff" then
    local b=target.bounding_box
    local area=math.max(1,(b.right_bottom.x-b.left_top.x)*(b.right_bottom.y-b.left_top.y))
    seconds=3+1.5*math.sqrt(area)
  elseif target.type=="tree" then
    seconds=.5+max_health/100+quantity*.2+mining_time*.4
  else
    seconds=1+math.sqrt(max_health)/18+quantity/20+mining_time*.3
  end
  return math.max(30,math.ceil(seconds*60*remaining))
end

function M.terrain(tiles,surface,kind)
  local work=0
  for _,tile in ipairs(tiles)do
    local name=surface.get_tile(tile.position).name
    local hardness=1
    if kind=="canal" then
      if name:find("refined%-concrete") then hardness=5
      elseif name:find("concrete") then hardness=4
      elseif name=="stone-path" then hardness=2 end
    end
    work=work+30*hardness
  end
  return math.max(1,work)
end
return M
