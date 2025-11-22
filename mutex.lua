local Mutex = {}
Mutex.__index = Mutex

function Mutex.new(eventName)
    return setmetatable({
        locked = false,
        queue = {},
        event = eventName or "__mutex"
    }, Mutex)
end

function Mutex:lock()
    if not self.locked then
        self.locked = true
        return
    end

    local co = coroutine.running()
    table.insert(self.queue, co)

    return coroutine.yield(self.event)
end

function Mutex:unlock()
    if #self.queue > 0 then
        local nextCo = table.remove(self.queue, 1)
        os.queueEvent(self.event)
    else
        self.locked = false
    end
end

return Mutex
