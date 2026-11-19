local M = {}

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", [['\'']]) .. "'"
end

local function run(cmd)
  local handle = io.popen(cmd .. " 2>&1; echo \"__EXIT:$?\"")
  if not handle then return false, "failed to run: " .. cmd end
  local out = handle:read("*a")
  handle:close()

  local code = tonumber(out:match("__EXIT:(%d+)%s*$"))
  out = out:gsub("__EXIT:%d+%s*$", ""):gsub("%s+$", "")
  return code == 0, out
end

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

function M.get_branches()
  local ok, out = run("git branch --format='%(refname:short)'")
  if not ok then return false, out end
  return true, split_lines(out)
end

function M.get_modified_files()
  local ok, out = run("git diff --name-only HEAD")
  if not ok then return false, out end
  return true, split_lines(out)
end

function M.branch_exists(branch_name)
  if not is_valid_name(branch_name) then return false end
  local ok = run("git rev-parse --verify --quiet " .. shell_quote("refs/heads/" .. branch_name))
  return ok
end

function M.create_branch(branch_name)
  if not is_valid_name(branch_name) then return false, "branch_name must be a non-empty string" end
  return run("git branch " .. shell_quote(branch_name))
end

function M.switch_to_branch(branch_name)
  if not is_valid_name(branch_name) then return false, "branch_name must be a non-empty string" end
  if M.branch_exists(branch_name) then
    return run("git switch " .. shell_quote(branch_name))
  end
  return run("git switch -c " .. shell_quote(branch_name))
end

function M.commit_changes(msg)
  if not is_valid_name(msg) then return false, "msg must be a non-empty string" end
  return run("git commit -a -m " .. shell_quote(msg))
end

function M.push_branch()
  return run("git push")
end

function M.pull_branch()
  return run("git pull")
end

return M
