-- Continuous orientation: 0 = north, 0.25 = east. Never quantize the chassis.
local M={}
function M.forward(car)
  local a=car.orientation*2*math.pi
  return {math.sin(a),-math.cos(a)}
end
function M.front_area(car)
  local v=M.forward(car);local r={-v[2],v[1]}
  local x,y=car.position.x+v[1]*3.25,car.position.y+v[2]*3.25
  local hx,hy=math.abs(v[1])*1.45+math.abs(r[1])*1.8,math.abs(v[2])*1.45+math.abs(r[2])*1.8
  return {{x-hx,y-hy},{x+hx,y+hy}}
end
function M.contact(car,preferred,cliffs)
  local f=M.forward(car);local r={-f[2],f[1]};local p=car.position
  local cx,cy=p.x+f[1]*2.65,p.y+f[2]*2.65
  local hx,hy=math.abs(f[1])*.25+math.abs(r[1])*1.36,math.abs(f[2])*.25+math.abs(r[2])*1.36
  local candidates=car.surface.find_entities_filtered({area={{cx-hx,cy-hy},{cx+hx,cy+hy}},type={"tree","simple-entity","cliff"}})
  local best,distance
  for _,e in pairs(candidates)do
    local eligible=cliffs and e.type=="cliff" or not cliffs and e.type=="tree" or e.type=="simple-entity" and e.prototype.count_as_rock_for_filtered_deconstruction
    if eligible and e.destructible then
      local b=e.bounding_box;local x=(b.left_top.x+b.right_bottom.x)/2-p.x;local y=(b.left_top.y+b.right_bottom.y)/2-p.y
      local ex=(b.right_bottom.x-b.left_top.x)/2;local ey=(b.right_bottom.y-b.left_top.y)/2
      local forward=x*f[1]+y*f[2];local across=x*r[1]+y*r[2]
      local ef=math.abs(f[1])*ex+math.abs(f[2])*ey;local er=math.abs(r[1])*ex+math.abs(r[2])*ey
      if forward+ef>=2.4 and forward-ef<=2.9 and math.abs(across)<=1.36+er then
        if e==preferred then return e end
        if not distance or forward-ef<distance then best=e;distance=forward-ef end
      end
    end
  end
  return best
end
return M
