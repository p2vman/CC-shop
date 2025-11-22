local EventLoop = {}
EventLoop.__index = EventLoop

function EventLoop.new()
    local self = setmetatable({}, EventLoop)
    self.ready = {}
    self.waiting = {}
    return self
end

function EventLoop:spawn(fn)
    local co = coroutine.create(fn)
    table.insert(self.ready, co)
    return co
end

function EventLoop:run()
    while true do
        local nextReady = {}
        for _, co in ipairs(self.ready) do
            if coroutine.status(co) ~= "dead" then
                local ok, event = coroutine.resume(co)
                if not ok then
                    print("Coroutine error:", event)
                elseif event then
                    self.waiting[event] = self.waiting[event] or {}
                    table.insert(self.waiting[event], co)
                else
                    table.insert(nextReady, co)
                end
            end
        end
        self.ready = nextReady

        if #self.ready == 0 and not next(self.waiting) then
            break
        end

        local eventData = table.pack(coroutine.yield())
        eventData = {table.unpack(eventData, 1, eventData.n)}
        local eventName = eventData[1]

        local waiting = self.waiting[eventName]
        self.waiting[eventName] = nil
        if waiting then
            for _, co in ipairs(waiting) do
                if coroutine.status(co) ~= "dead" then
                    local ok, nextEvent = coroutine.resume(co, table.unpack(eventData))
                    if not ok then
                        print("Coroutine error:", nextEvent)
                    elseif nextEvent then
                        self.waiting[nextEvent] = self.waiting[nextEvent] or {}
                        table.insert(self.waiting[nextEvent], co)
                    else
                        table.insert(self.ready, co)
                    end
                end
            end
        end
    end
end

return EventLoop
