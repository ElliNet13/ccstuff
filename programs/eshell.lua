-- ElliNet13 Terminal

local fs, term, multishell, textutils, os = fs, term, multishell, textutils, os

local builtins = {}
local jobs = {}
local jobCounter = 1
local currentJob = nil
local running = true

local function split(input, sep)
  local result = {}
  for token in string.gmatch(input, "[^" .. sep .. "]+") do
    table.insert(result, token)
  end
  return result
end

local function getPrompt()
  local dir = shell and shell.dir and shell.dir() or fs.getDir(".")
  local label = os.getComputerLabel()
  local id = os.getComputerID()
  if label then
    return string.format("%s:%s:%d> ", dir, label, id)
  else
    return string.format("%s:%d> ", dir, id)
  end
end

local function resolve(path)
  if fs.exists(path) then return path end
  if fs.exists("/usr/bin/" .. path) then return "/usr/bin/" .. path end
  return nil
end

local function execute(command, background)
  local parts = split(command, " ")
  local cmd = table.remove(parts, 1)
  
  local path = resolve(cmd)
  if path then
    -- Run external executable (don't print anything before running)
    local f = fs.open(path, "r")
    local ok, err = os.run({}, path, unpack(parts))
    if not ok then print("Error:", err) end
  elseif builtins[cmd] then
    local function run()
      builtins[cmd](unpack(parts))
    end
    if background then
      local id = jobCounter
      jobCounter = jobCounter + 1
      local pid = multishell.launch({}, function()
        run()
        jobs[id] = nil
      end)
      jobs[id] = { pid = pid, cmd = command }
      print("[" .. id .. "] " .. pid)
    else
      currentJob = cmd
      run()
      currentJob = nil
    end
  else
    print(cmd .. ": command not found")
  end
end


-- Builtin commands

builtins["clear"] = function() term.clear() term.setCursorPos(1, 1) end

builtins["ls"] = function(path)
  path = path or "."
  if not fs.exists(path) then
    print("ls: cannot access '" .. path .. "': No such file or directory")
    return
  end
  for _, file in ipairs(fs.list(path)) do
    write(file .. "  ")
  end
  print()
end

builtins["reboot"] = os.reboot
builtins["id"] = function() local id = os.getComputerID() if id then print(id) else print("id: unknown") end end
builtins["label"] = function(arg)
  if arg then
    os.setComputerLabel(arg)
  end
  print(os.getComputerLabel() or "")
end

builtins["cat"] = function(file)
  if not file or not fs.exists(file) then print("cat: missing or invalid file") return end
  local h = fs.open(file, "r")
  print(h.readAll())
  h.close()
end

builtins["touch"] = function(file)
  if not file then print("touch: missing file") return end
  local h = fs.open(file, "w") h.close()
end

builtins["rm"] = function(file)
  if not file or not fs.exists(file) then print("rm: file not found") return end
  fs.delete(file)
end

builtins["echo"] = function(...)
  print(table.concat({...}, " "))
end

builtins["jobs"] = function()
  for id, job in pairs(jobs) do
    print("[" .. id .. "] PID:" .. job.pid .. " CMD:" .. job.cmd)
  end
end

builtins["fg"] = function(id)
  id = tonumber(id)
  if jobs[id] then
    multishell.setFocus(jobs[id].pid)
  else
    print("fg: job not found")
  end
end

builtins["kill"] = function(id)
  id = tonumber(id)
  if jobs[id] then
    multishell.terminate(jobs[id].pid)
    jobs[id] = nil
  else
    print("kill: job not found")
  end
end

-- New exit command to quit the shell
builtins["exit"] = function()
  running = false
end

-- Autocomplete
local function autocomplete(input)
  local files = fs.list(".")
  local suggestions = {}
  for _, name in ipairs(files) do
    if name:sub(1, #input) == input then
      table.insert(suggestions, name)
    end
  end
  for name in pairs(builtins) do
    if name:sub(1, #input) == input then
      table.insert(suggestions, name)
    end
  end
  return suggestions
end

-- Main Loop
while running do
  write(getPrompt())
  local input = read(nil, nil, function(text)
    return autocomplete(text)
  end)

  if input:match("&$") then
    execute(input:sub(1, -2):gsub("%s+$", ""), true)
  elseif input:match(">>%?") then
    local cmd, outfile = input:match("^(.-)%s*>+%s*(.-)%s*$")
    local mode = input:find(">>") and "a" or "w"
    local h = fs.open(outfile, mode)
    local oldWrite = term.redirect(h)
    execute(cmd)
    term.redirect(oldWrite)
    h.close()
  else
    execute(input)
  end
end
