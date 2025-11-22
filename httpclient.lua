HttpClient = {}
HttpClient.__index = HttpClient

function HttpClient.new(headers)
    return setmetatable({
        headers = headers or {}
    }, HttpClient)
end

function HttpClient:get(url, headers)
    local response = http.get(url, headers or self)
    if not response then
        return nil, "Failed to make HTTP GET request"
    end

    local body = response.readAll()
    response.close()
    return body
end

function HttpClient:post(url, data, headers)
    local response = http.post(url, textutils.serialiseJSON(data), headers or self)
    if not response then
        return nil, "Failed to make HTTP POST request"
    end

    local body = response.readAll()
    response.close()
    return body
    
end

return HttpClient