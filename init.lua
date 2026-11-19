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


-- git ------------------------------------------------------------------------
-- cmd+g opens a picker of git actions; each is also a standalone action
-- (rex do git_push). Commands are typed into the focused shell when it's idle,
-- otherwise they run in a pane split below it.

local config_dir = (debug and debug.getinfo(1, "S").source:match("^@(.+)/[^/]+$"))
                   or (os.getenv("HOME") .. "/.config/rex")
package.path = config_dir .. "/?.lua;" .. package.path
package.loaded.git = nil -- pick up edits on config reload
local git = require("git")

local shells = { fish = true, zsh = true, bash = true, sh = true }

local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- the server's PATH doesn't include the rex CLI
local rex_bin = os.getenv("HOME")
  .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
local f = io.open(rex_bin)
if f then f:close() else rex_bin = "rex" end

-- call a terminal method on the action's block (init.lua can't invoke block
-- methods directly, so go through the CLI)
local function block_call(ctx, method, args)
  local argv = { rex_bin, "block", "call", "-s", ctx.session_id, "-b", ctx.block_id, method }
  for _, a in ipairs(args or {}) do argv[#argv + 1] = a end
  local res = rex.exec.start(argv):wait()
  if not res.ok then error(method .. ": " .. res.stderr) end
  return res.stdout ~= "" and rex.json.decode(res.stdout) or nil
end

-- the focused pane's directory and whether it's sitting at a shell prompt
local function git_context(ctx)
  if not ctx.block_id then error("no focused terminal") end
  local proc = block_call(ctx, "process") or {}
  local fg = proc.foreground or {}
  local pwd = block_call(ctx, "pwd") or {}
  local dir = pwd.pwd and url_decode(pwd.pwd:gsub("^file://[^/]*", "")) or fg.cwd
  if not dir or dir == "" then error("can't tell the focused pane's directory") end

  local ok, root = git.repo_root(dir)
  if not ok then error("not a git repository: " .. dir) end
  return { ctx = ctx, dir = root, shell = shells[fg.name] and fg.name or nil }
end

-- quote for wherever run_in_terminal will run the command
local function q(g, s) return git.quote(s, g.shell) end

local function run_in_terminal(g, cmd, opts)
  opts = opts or {}
  if g.shell then
    local res = rex.exec.start{ rex_bin, "send", "-s", g.ctx.session_id, "-b", g.ctx.block_id, cmd .. "\r" }:wait()
    if not res.ok then error("couldn't type into the pane: " .. res.stderr) end
    return
  end
  local argv = { rex_bin, "split", "-s", g.ctx.session_id, "-b", g.ctx.block_id,
                 "--split=below", "--ratio", "35", "-c", g.dir }
  if opts.keep_open ~= false then argv[#argv + 1] = "--keep-open" end
  for _, a in ipairs{ "--", "sh", "-c", cmd } do argv[#argv + 1] = a end
  local res = rex.exec.start(argv):wait()
  if not res.ok then error("couldn't open a pane: " .. res.stderr) end
end

local function pick(title, placeholder, items)
  local id, why, detail = rex.ui.pick{ title = title, placeholder = placeholder, items = items }
  if id == nil and why ~= "cancelled" and why ~= "timeout" then
    error("picker " .. why .. (detail and (": " .. detail) or ""))
  end
  return id
end

local function input(title, placeholder)
  local text, why, detail = rex.ui.input{ title = title, placeholder = placeholder }
  if text == nil and why ~= "cancelled" and why ~= "timeout" then
    error("input " .. why .. (detail and (": " .. detail) or ""))
  end
  if text == nil or text:match("^%s*$") then return nil end
  return text
end

local function must(ok, value)
  if not ok then error(value) end
  return value
end

-- builders return cmd or nil, err
local function built(cmd, err)
  if not cmd then error(err) end
  return cmd
end

local git_actions = {}

local function git_action(def)
  git_actions[#git_actions + 1] = def
  rex.action{
    name  = def.name,
    title = "Git: " .. def.title,
    run   = function(ctx) return def.run(git_context(ctx)) end,
  }
end

git_action{ name = "git_status", title = "Status", detail = "git status",
  run = function(g) run_in_terminal(g, "git status") end }

git_action{ name = "git_diff", title = "Diff", detail = "git diff HEAD",
  run = function(g) run_in_terminal(g, "git --no-pager diff HEAD") end }

git_action{ name = "git_log", title = "Log", detail = "last 20 commits",
  run = function(g) run_in_terminal(g, "git --no-pager log --oneline --graph --decorate -20") end }

git_action{ name = "git_commit", title = "Commit all changes…", detail = "git add -A && git commit",
  run = function(g)
    local changed = must(git.get_modified_files(g.dir))
    if #changed == 0 then error("nothing to commit") end
    local msg = input("Commit " .. #changed .. " changed file(s)", "Commit message")
    if not msg then return end
    run_in_terminal(g, built(git.commit_changes(msg, g.shell)))
  end }

git_action{ name = "git_amend", title = "Amend last commit", detail = "add all changes, keep message",
  run = function(g) run_in_terminal(g, git.amend_commit()) end }

git_action{ name = "git_pull", title = "Pull", detail = "git pull",
  run = function(g) run_in_terminal(g, git.pull_branch()) end }

git_action{ name = "git_push", title = "Push", detail = "sets upstream if missing",
  run = function(g) run_in_terminal(g, git.push_branch(g.dir)) end }

local function new_branch(g)
  local name = input("New branch", "Branch name")
  if not name then return end
  run_in_terminal(g, built(git.switch_to_branch(g.dir, name, g.shell)))
end

git_action{ name = "git_new_branch", title = "New branch…", detail = "git switch -c",
  run = new_branch }

git_action{ name = "git_switch", title = "Switch branch…", detail = "local or remote branch",
  run = function(g)
    local _, current = git.current_branch(g.dir)
    local items, have = {}, {}
    for _, b in ipairs(must(git.get_branches(g.dir))) do
      have[b] = true
      if b ~= current then items[#items + 1] = { id = "local:" .. b, title = b } end
    end
    local ok, remotes = git.get_remote_branches(g.dir)
    for _, rb in ipairs(ok and remotes or {}) do
      if not have[rb:match("^[^/]+/(.+)$")] then
        items[#items + 1] = { id = "remote:" .. rb, title = rb, subtitle = "remote" }
      end
    end
    items[#items + 1] = { id = "new", title = "New branch…" }

    local id = pick("Switch from " .. current, "Filter branches", items)
    if not id then return end
    if id == "new" then return new_branch(g) end
    local kind, name = id:match("^(%a+):(.+)$")
    if kind == "remote" then
      run_in_terminal(g, git.track_remote_branch(name, g.shell))
    else
      run_in_terminal(g, built(git.switch_to_branch(g.dir, name, g.shell)))
    end
  end }

git_action{ name = "git_stash", title = "Stash changes", detail = "includes untracked files",
  run = function(g) run_in_terminal(g, "git stash push -u") end }

git_action{ name = "git_stash_pop", title = "Pop stash…", detail = "git stash pop",
  run = function(g)
    local items = {}
    for _, line in ipairs(must(git.get_stashes(g.dir))) do
      local ref, subject = line:match("^([^\t]+)\t(.*)$")
      if ref then items[#items + 1] = { id = ref, title = subject, subtitle = ref } end
    end
    if #items == 0 then error("no stashes") end
    local ref = pick("Pop stash", "Filter stashes", items)
    if not ref then return end
    run_in_terminal(g, "git stash pop " .. q(g, ref))
  end }

git_action{ name = "git_lazygit", title = "Open lazygit", detail = "full git UI",
  run = function(g) run_in_terminal(g, "lazygit", { keep_open = false }) end }

rex.action{
  name  = "git_menu",
  title = "Git…",
  run = function(ctx)
    local g = git_context(ctx)
    local _, branch = git.current_branch(g.dir)
    local ok, changed = git.get_modified_files(g.dir)
    local title = "Git · " .. (branch ~= "" and branch or "detached")
    if ok and #changed > 0 then title = title .. " · " .. #changed .. " changed" end

    local items = {}
    for _, a in ipairs(git_actions) do
      items[#items + 1] = { id = a.name, title = a.title, subtitle = a.detail }
    end
    local id = pick(title, "Git action", items)
    if not id then return end
    for _, a in ipairs(git_actions) do
      if a.name == id then return a.run(g) end
    end
  end,
}

rex.bind("cmd+g", "git_menu")

rex.action {
  name = "open_site",
  title = "Open a website",
  run = function(ctx, args)
    local url, why = rex.ui.input {
      title = "Website URL",
      placeholder = "https://sxitch.app",
      value = "https://",
      confirm = "Open website",
    }
    if url == nil then return end

    rex.exec{ "open", "-u", url }
  end
}

rex.bind("cmd+shift+k", "open_site")
