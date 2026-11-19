-- pane creation using vim directions
rex.bind("ctrl+p", "client.mode.enter", { name = "spliter" })

rex.bind("spliter/h", "pane.split", { direction = "left" })
rex.bind("spliter/l", "pane.split", { direction = "right" })
rex.bind("spliter/k", "pane.split", { direction = "up" })
rex.bind("spliter/j", "pane.split", { direction = "down" })

rex.bind("cmd+r", "client.mode.enter", { name = "resize" })

rex.bind("resize/h", "pane.resize", { direction = "left" })
rex.bind("resize/l", "pane.resize", { direction = "right" })
rex.bind("resize/k", "pane.resize", { direction = "up" })
rex.bind("resize/j", "pane.resize", { direction = "down" })

rex.bind("cmd+shift+f", "client.mode.enter", { name = "focus", once = true })

rex.bind("focus/h", "pane.focus", { direction = "left" })
rex.bind("focus/l", "pane.focus", { direction = "right" })
rex.bind("focus/k", "pane.focus", { direction = "up" })
rex.bind("focus/j", "pane.focus", { direction = "down" })

local coding = os.getenv("HOME") .. "/Documents/coding"

local function is_dir(path)
  local f = io.open(path .. "/.") -- only opens if path is a directory
  if f then f:close() end
  return f ~= nil
end

local function shell(opts)
  return rex.layout.block{
    flavor  = "com.superlogical.terminal.shell",
    options = opts,
  }
end

-- subfolder names of path, sorted, skipping hidden ones
local function subdirs(path)
  local res = rex.exec.start{ "find", path, "-mindepth", "1", "-maxdepth", "1",
                              "-type", "d", "-not", "-name", ".*" }:wait()
  local names = {}
  for line in res.stdout:gmatch("[^\n]+") do
    names[#names + 1] = line:match("[^/]+$")
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

-- pick a folder inside path; returns nil if the picker was dismissed
local function pick_dir(title, path)
  if not rex.ui then error("rex.ui needs a newer Rex (control API revision 17)") end
  local items = {}
  for _, name in ipairs(subdirs(path)) do
    items[#items + 1] = { id = name, icon = "folder" }
  end
  local id, why, detail = rex.ui.pick{ title = title, placeholder = "Filter folders", items = items }
  if id == nil and why ~= "cancelled" and why ~= "timeout" then
    error("picker " .. why .. (detail and (": " .. detail) or ""))
  end
  return id
end

-- rex do new_space project=bobrwm
-- rex do new_space project=akita sub=akitavault
-- missing args are asked for with a picker
rex.action{
  name  = "new_space",
  title = "Open a new workspace…",
  args  = { project = "string?", sub = "string?" },
  run = function(ctx, args)
    local project = args.project or pick_dir("Project", coding)
    if not project then return end
    local dir = coding .. "/" .. project

    if project == "akita" then
      local sub = args.sub or pick_dir("Akita folder", dir)
      if not sub then return end
      dir = dir .. "/" .. sub
    end
    if not is_dir(dir) then error("no such directory: " .. dir) end

    local layout = rex.layout.horizontal(0.5,
      shell{ cwd = dir },                                  -- left pane
      rex.layout.vertical(0.6,
        shell{ cwd = dir },                                -- top right
        shell{ cwd = dir }                                 -- bottom right
      )
    )
    local w, err = rex.session.new_window{ layout = layout }
    if not w then error(err) end
    return w
  end,
}

rex.bind("ctrl+opt+m", "new_space")  -- optional key binding

