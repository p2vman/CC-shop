-- string_utils.lua
local string_utils = {}
function string_utils.contains(str, sub)
    return str:find(sub, 1, true) ~= nil
end
function string_utils.startswith(str, start)
    return str:sub(1, #start) == start
end
function string_utils.endswith(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end
function string_utils.replace(str, old, new)
    local s = str
    local search_start_idx = 1
    while true do
        local start_idx, end_idx = s:find(old, search_start_idx, true)
        if not start_idx then break end
        local postfix = s:sub(end_idx + 1)
        s = s:sub(1, (start_idx - 1)) .. new .. postfix
        search_start_idx = -1 * postfix:len()
    end
    return s
end
function string_utils.insert(str, pos, text)
    return str:sub(1, pos - 1) .. text .. str:sub(pos)
end

-- split utility
local function split(input_string, separator_pattern)
    local result_table = {}
    local pattern = "(.-)" .. (separator_pattern or "")
    local last_pos = 1
    for part in string.gmatch(input_string, pattern) do
        table.insert(result_table, part)
        last_pos = last_pos + #part + #(separator_pattern or "")
    end
    if last_pos <= #input_string then
        table.insert(result_table, string.sub(input_string, last_pos))
    end
    return result_table
end

-- Peripheral setup
local drive = assert(peripheral.find("drive"), "Driver not found.")
local monitor = assert(peripheral.find("monitor"), "Monitor not found.")
local input_vault = assert(peripheral.wrap("create:item_vault_0"), "Input vault not found.")
local output_vault = assert(peripheral.wrap("create:item_vault_1"), "Output vault not found.")
local storage_item_vault = assert(peripheral.wrap("create:item_vault_2"), "Storage valut not found.")

-- External modules
local EventLoop = require "EventLoop"
local expect = require "cc.expect".expect
local mutex = require "mutex"

-- Global state
local loop = EventLoop.new()
local telemetry = false
local index, count = 1, 1
local input_vault_items = {}
local items = {}

-- Config loading
local function loadConfig()
    local conf
    if drive.isDiskPresent() then
        conf = fs.combine(drive.getMountPath(), "config.json")
    else
        conf = "config.json"
    end
    if fs.exists(conf) then
        local file = fs.open(conf, "r")
        local config = textutils.unserialiseJSON(file.readAll())
        file.close()
        return config
    end
    return nil
end

local function loadMappings()
    local conf
    if drive.isDiskPresent() then
        conf = fs.combine(drive.getMountPath(), "IdToName.json")
    else
        conf = "IdToName.json"
    end
    if fs.exists(conf) then
        local file = fs.open(conf, "r")
        local config = textutils.unserialiseJSON(file.readAll())
        file.close()
        return config
    end
    return nil
end

local mappings = assert(loadMappings(), "Mappings not found.")
local function mappID(id) return mappings[id] or id end
local config = assert(loadConfig(), "Config not found.")

-- Inventory indexing
local function indexing()
    local names = peripheral.getNames()
    local chests = {}
    for _, value in ipairs(names) do
        if string_utils.startswith(value, "create:item_vault_2") then
            table.insert(chests, peripheral.wrap(value))
        end
    end
    local _items = {}
    for _, chest in ipairs(chests) do
        for _, item in pairs(chest.list()) do
            _items[item.name] = (_items[item.name] or 0) + item.count
        end
    end
    items = _items
    _items = {}
    for _, item in pairs(input_vault.list()) do
        _items[item.name] = (_items[item.name] or 0) + item.count
    end
    input_vault_items = _items
end

-- Monitor setup
monitor.setTextScale(0.5)
local width, heigth = monitor.getSize()
local function TextArrayWidth(list)
    local width = 1
    for _, value in ipairs(list) do
        width = math.max(width, #value.title)
    end
    return width
end
local wh = math.min(19, TextArrayWidth(config))
local list_window = window.create(monitor, 1, 1, wh, heigth)
list_window.setBackgroundColor(colors.gray)
list_window.setTextColor(colors.black)
local view = window.create(monitor, wh+1, 1, width-wh-12, heigth)
view.width = width-wh-12
view.setBackgroundColor(colors.lightGray)
view.setTextColor(colors.black)
local by_view = window.create(monitor, width-11, 1, width-wh, heigth)
by_view.width = width-wh
by_view.setBackgroundColor(colors.gray)
by_view.setTextColor(colors.black)
local by_mutex = mutex.new("buy")

-- Utility for writing with padding
function view:Swrite(text)
    self.write(text .. string.rep(" ", self.width - #text))
end
function by_view:Swrite(text)
    self.write(text .. string.rep(" ", self.width - #text))
end

-- Touch event handler
loop:spawn(function()
    while true do
        local eventData = { os.pullEventRaw("monitor_touch") }
        local _, _, x, y = table.unpack(eventData)
        if x > wh then
            if (x == 46 or x == 47) and y == 2 then count = count + 5
            elseif (x == 56 or x == 57) and y == 2 then count = count - 5
            elseif (x == 49) and y == 2 then count = count + 1
            elseif (x == 54) and y == 2 then count = count - 1
            elseif (x > 50 and x < 54) and y == 4 then dump()
            elseif (x > 50 and x < 55) and y == 3 then buy() end
            count = math.min(math.max(count, 1), 64)
        else
            index = y
        end
    end
end)

-- Transfer items for order
local function transfer(order)
    for _, value in ipairs(order.price) do
        for idx, _value in ipairs(input_vault.list()) do
            if value.id == _value.name and _value.count >= value.count then
                input_vault.pushItems(peripheral.getName(storage_item_vault), idx, value.count)
                break
            end
        end
    end
    for index, value in ipairs(storage_item_vault.list()) do
        if value.name == order.result.id and value.count >= order.result.count then
            storage_item_vault.pushItems(peripheral.getName(output_vault), index, order.result.count)
            break
        end
    end
end

-- Buy logic
function buy()
    by_mutex:lock()
    pcall(function ()
        local order = config[index]
        local _count = count
        for i = 1, _count do
            if (items[order.result.id] or 0) < order.result.count then goto coroutine end
            for _, value in ipairs(order.price) do
                if (input_vault_items[value.id] or 0) < value.count then goto coroutine end
            end
            transfer(order)
            ::coroutine::
        end
    end)
    by_mutex:unlock()
    indexing()
end

-- Dump all items
function dump()
    for idx, _ in ipairs(input_vault.list()) do
        input_vault.pushItems(peripheral.getName(output_vault), idx)
    end
end

-- Telemetry (stub)
if telemetry then
    loop:spawn(function() while true do end end)
end

-- Indexing loop
loop:spawn(function()
    while true do
        indexing()
        sleep(1/8)
    end
end)

-- Marquee state
local marquee_offset, marquee_timer = 0, 0
local marquee_speed = 0.14

-- Render loop
loop:spawn(function()
    while true do
        monitor.clear()
        marquee_timer = marquee_timer + (1/8)
        if marquee_timer >= marquee_speed then
            marquee_timer = 0
            marquee_offset = marquee_offset + 1
        end
        for _index, value in ipairs(config) do
            list_window.setCursorPos(1, _index)
            if _index == index then
                list_window.setTextColor(colors.blue)
            else
                list_window.setTextColor(colors.black)
            end
            local title = value.title
            if #title > wh then
                local sep = " | "
                local marquee_text = title .. sep
                local offset = marquee_offset % #marquee_text
                local display = ""
                if offset + wh <= #marquee_text then
                    display = marquee_text:sub(offset+1, offset+wh)
                else
                    local part1 = marquee_text:sub(offset+1)
                    local part2 = marquee_text:sub(1, wh-#part1)
                    display = part1 .. part2
                end
                list_window.write(display)
            else
                list_window.write(title .. string.rep(" ", wh - #title))
            end
        end
        local curent = config[index]
        if curent then
            view.setCursorPos(1, 1)
            view:Swrite(curent.title)
            view.setCursorPos(1, 2)
            view:Swrite("result:")
            view.setCursorPos(1, 3)
            if (items[curent.result.id] or 0) < curent.result.count * count then
                view.setTextColor(colors.red)
            end
            view:Swrite("  " .. mappID(curent.result.id) .. "*" .. curent.result.count * count)
            view.setTextColor(colors.black)
            view.setCursorPos(1, 4)
            view:Swrite("price:")
            for idx, value in ipairs(curent.price) do
                view.setCursorPos(1, idx+4)
                if (input_vault_items[value.id] or 0) < value.count * count then
                    view.setTextColor(colors.red)
                end
                view:Swrite("  " .. mappID(value.id) .. "*" .. value.count * count)
                view.setTextColor(colors.black)
            end
            local l = #curent.price+5
            view.setCursorPos(1, l)
            view:Swrite("input:")
            for name, value in pairs(input_vault_items) do
                view.setCursorPos(1, l+1)
                view:Swrite("  " .. mappID(name) .. "*" .. value)
                l = l + 1
            end
        end
        by_view.setCursorPos(1, 1)
        by_view:Swrite("count: " .. count)
        by_view.setCursorPos(1, 2)
        by_view:Swrite("++ +    - --")
        if false then
            by_view.setTextColor(colors.green)
        else
            by_view.setTextColor(colors.red)
        end
        by_view.setCursorPos(1, 3)
        by_view:Swrite("     Buy")
        by_view.setTextColor(colors.blue)
        by_view.setCursorPos(1, 4)
        by_view:Swrite("     Dump")
        by_view.setTextColor(colors.black)
        sleep(1/8)
    end
end)

loop:run()