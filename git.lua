-- git helpers for Rex actions.
-- Queries run synchronously in a directory and return their output;
-- builders return a shell command string to be run in a terminal.
local M = {}

local function split_lines(s)
  local lines = {}
  for line in s:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  return lines
end

local function is_valid_name(name)
  return type(name) == "string" and name ~= ""
end

-- run git in dir; returns ok, output (stdout on success, stderr on failure)
local function run(dir, argv)
  local cmd = { "git" }
  for _, a in ipairs(argv) do cmd[#cmd + 1] = a end
  local p, err = rex.exec.start(cmd, { cwd = dir })
  if not p then return false, err end
  local res = p:wait()
  local out = (res.ok and res.stdout or (res.stderr ~= "" and res.stderr or res.stdout)):gsub("%s+$", "")
  return res.ok, out
end

-- quote s for the given shell ("fish" or anything POSIX)
function M.quote(s, shell)
  s = tostring(s)
  if shell == "fish" then
    return "'" .. s:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
  end
  return "'" .. s:gsub("'", [['\'']]) .. "'"
end

-- queries ------------------------------------------------------------------

function M.repo_root(dir)
  return run(dir, { "rev-parse", "--show-toplevel" })
end

function M.current_branch(dir)
  return run(dir, { "branch", "--show-current" })
end

function M.get_branches(dir)
  local ok, out = run(dir, { "branch", "--format=%(refname:short)" })
  if not ok then return false, out end
  return true, split_lines(out)
end

function M.get_remote_branches(dir)
  local ok, out = run(dir, { "branch", "-r", "--format=%(refname:short)" })
  if not ok then return false, out end
  local names = {}
  for _, name in ipairs(split_lines(out)) do
    if not name:match("/HEAD$") and name:find("/") then names[#names + 1] = name end
  end
  return true, names
end

function M.get_modified_files(dir)
  local ok, out = run(dir, { "status", "--porcelain" })
  if not ok then return false, out end
  return true, split_lines(out)
end

function M.get_stashes(dir)
  local ok, out = run(dir, { "stash", "list", "--format=%gd\t%s" })
  if not ok then return false, out end
  return true, split_lines(out)
end

function M.branch_exists(dir, branch_name)
  if not is_valid_name(branch_name) then return false end
  return (run(dir, { "rev-parse", "--verify", "--quiet", "refs/heads/" .. branch_name }))
end

function M.has_upstream(dir)
  return (run(dir, { "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" }))
end

-- command builders ---------------------------------------------------------

function M.switch_to_branch(dir, branch_name, shell)
  if not is_valid_name(branch_name) then return nil, "branch_name must be a non-empty string" end
  if M.branch_exists(dir, branch_name) then
    return "git switch " .. M.quote(branch_name, shell)
  end
  return "git switch -c " .. M.quote(branch_name, shell)
end

-- checks out origin/foo as a local tracking branch foo
function M.track_remote_branch(remote_branch, shell)
  return "git switch --track " .. M.quote(remote_branch, shell)
end

function M.commit_changes(msg, shell)
  if not is_valid_name(msg) then return nil, "msg must be a non-empty string" end
  return "git add -A && git commit -m " .. M.quote(msg, shell)
end

function M.amend_commit()
  return "git add -A && git commit --amend --no-edit"
end

function M.push_branch(dir)
  if M.has_upstream(dir) then return "git push" end
  return "git push -u origin HEAD"
end

function M.pull_branch()
  return "git pull"
end

return M
