-- Only used to clean up LuaRendering overlays saved by versions <= 0.5.0.
-- Both current modes are drawn by their native car prototypes, including ghosts.
local M = {}
function M.destroy(state)
  for _, role in ipairs{"vehicle", "tracks", "head"} do
    local object = state["motion_" .. role]
    if object and object.valid then object.destroy() end
    state["motion_" .. role] = nil
  end
end
return M
