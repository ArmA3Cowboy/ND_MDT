local Bridge = {}

---@return table
function Bridge.getPlayerInfo()
    local PlayerData = exports.qbx_core:GetPlayerData()
    local job = PlayerData.job or {}
    local charinfo = PlayerData.charinfo or {}
    local metadata = PlayerData.metadata or {}
    return {
        firstName = charinfo.firstname or "",
        lastName = charinfo.lastname or "",
        job = job.name or "",
        jobLabel = job.label or "",
        callsign = metadata.callsign or "",
        img = metadata.img or "user.jpg",
        isBoss = job.isboss or false,
    }
end

---@param job string
---@return boolean
function Bridge.hasAccess(job)
    return config.policeAccess[job] or config.fireAccess[job]
end

---@return string
function Bridge.rankName()
    local job = exports.qbx_core:GetPlayerData().job or {}
    return (job.grade and job.grade.name) or ""
end

---@param id string
---@param info table
---@return table
--- info is from returned profiles in server.lua
function Bridge.getCitizenInfo(id, info)
    return {
        img = info.img or "user.jpg",
        characterId = id,
        firstName = info.firstName,
        lastName = info.lastName,
        dob = info.dob,
        gender = info.gender,
        phone = info.phone,
        ethnicity = info.ethnicity
    }
end

function Bridge.getRanks(job)
    local ranks = lib.callback.await("ND_MDT:getRanks", false, job)
    if not ranks then return end

    local options = {}
    for k, v in pairs(ranks) do
        options[#options+1] = {
            value = k,
            label = v.name
        }
    end

    return options, job
end

---@param table any
---@return table
function Bridge.FillInVehData(table)
    for k, v in pairs(table) do
        table[k].model = GetDisplayNameFromVehicleModel(v.model)
        table[k].make = GetMakeNameFromVehicleModel(v.model)
        table[k].class = VehicleClasses and VehicleClasses[GetVehicleClassFromName(v.model)]
    end
    return table
end

return Bridge
