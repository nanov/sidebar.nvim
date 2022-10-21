
local M = {}
local api = vim.api
local luv = vim.loop

--- Reverse the order of elements in some `list`.
--- @param list table
--- @return table reversed
function M.reverse(list)
  local reversed = {}
  while #reversed < #list do
    reversed[#reversed + 1] = list[#list - #reversed]
  end
  return reversed
end

--- Insert a value between the elements of a list
--- @param list table
--- @param value any
--- @return table
function M.intersperse(list, value)
  local result = {}
  for i = 1, #list - 1 do
    table.insert(result, list[i])
    table.insert(result, value)
  end
  table.insert(result, list[#list])
  return result
end

function M.empty_message(text)
  local line = " " .. tostring(text)
  return {
    lines = { line },
    hl = { { "SidebarNvimComment", 0, 0, #line } },
  }
end

function M.echo_warning(msg)
    api.nvim_command("echohl WarningMsg")
    api.nvim_command("echom '[SidebarNvim] " .. msg:gsub("'", "''") .. "'")
    api.nvim_command("echohl None")
end

function M.escape_keycode(key)
    return key:gsub("<", "["):gsub(">", "]")
end

function M.unescape_keycode(key)
    return key:gsub("%[", "<"):gsub("%]", ">")
end

function M.sidebar_nvim_callback(key)
    return string.format(":lua require('sidebar-nvim.lib').on_keypress('%s')<CR>", M.escape_keycode(key))
end

function M.sidebar_nvim_cursor_move_callback(direction)
    return string.format(":lua require('sidebar-nvim')._on_cursor_move('%s')<CR>", direction)
end

local function get_builtin_section(name)
    local ret, result = pcall(require, "sidebar-nvim.builtin." .. name)
    if not ret then
        M.echo_warning("error trying to load section: " .. name)
        M.echo_warning(tostring(result))
        return nil
    end

    return result
end

function M.resolve_section(index, section)
    if type(section) == "string" then
        return get_builtin_section(section)
    elseif type(section) == "table" then
        return section
    end

    M.echo_warning("invalid SidebarNvim section at: index=" .. index .. " section=" .. section)
    return nil
end

function M.is_instance(o, class)
    while o do
        o = getmetatable(o)
        if class == o then
            return true
        end
    end
    return false
end

-- Reference: https://github.com/hoob3rt/lualine.nvim/blob/master/lua/lualine/components/filename.lua#L9

local function count(base, pattern)
    return select(2, string.gsub(base, pattern, ""))
end

local function make_path_relative_to_home(filepath)
    return filepath:gsub(luv.os_homedir(), '~')
end

function M.shorten_path(path)
    path = make_path_relative_to_home(path)
    return path
end

function M.shortest_path(path)
    path = make_path_relative_to_home(path)

    local sep = package.config:sub(1, 1)

    for _ = 0, count(path, sep) do
        -- ('([^/])[^/]+%/', '%1/', 1)
        path = path:gsub(string.format("([^%s])[^%s]+%%%s", sep, sep, sep), "%1" .. sep, 1)
    end

    return path
end

function M.dir(path)
    return path:match("^(.+/)")
end

function M.filename(path)
    local split = vim.split(path, "/")
    return split[#split]
end

function M.truncate(s, size)
    local length = #s

    if length <= size then
        return s
    else
        return s:sub(1, size) .. "…"
    end
end

-- execute async command and parse result into loclist items
function M.async_cmd(command, args, callback)
    local stdout = luv.new_pipe(false)
    local stderr = luv.new_pipe(false)
    local chunks = {}

    local handle
    handle = luv.spawn(command, { args = args, stdio = { nil, stdout, stderr }, cwd = luv.cwd() }, function()

        if callback then
            callback(chunks)
        end

        luv.read_stop(stdout)
        luv.read_stop(stderr)
        stdout:close()
        stderr:close()
        handle:close()
    end)

    luv.read_start(stdout, function(err, data)
        if err ~= nil then
            vim.schedule(function()
                M.echo_warning(err)
            end)
        end

        if data == nil then
            return
        end

        table.insert(chunks, data)
    end)

    luv.read_start(stderr, function(err, data)
        if data == nil then
            return
        end

        if err ~= nil then
            vim.schedule(function()
                M.echo_warning(err)
            end)
        end
    end)
end

-- @param opts table
-- @param opts.modified boolean filter buffers by modified or not
function M.get_existing_buffers(opts)
    return vim.tbl_filter(function(buf)
        local modified_filter = true
        if opts and opts.modified ~= nil then
            local is_ok, is_modified = pcall(api.nvim_buf_get_option, buf, "modified")

            if is_ok then
                modified_filter = is_modified == opts.modified
            end
        end

        return api.nvim_buf_is_valid(buf) and vim.fn.buflisted(buf) == 1 and modified_filter
    end, api.nvim_list_bufs())
end

return M
