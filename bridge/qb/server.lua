local Bridge = {}

SetTimeout(500, function()
    local resourceName = GetCurrentResourceName()
    local sqlFiles = {
        "bridge/qb/database/bolos.sql",
        "bridge/qb/database/records.sql",
        "bridge/qb/database/reports.sql",
        "bridge/qb/database/weapons.sql",
        "bridge/qb/database/alterQbox-DB.sql"
    }
    for i = 1, #sqlFiles do
        local file = LoadResourceFile(resourceName, sqlFiles[i])
        if file then MySQL.query(file) end
    end
end)

local function getPlayerSource(citizenid)
    local players = exports.qbx_core:GetQBPlayers()
    for src, player in pairs(players) do
        if player.citizenid == citizenid then
            return src
        end
    end
    return nil
end

local function findCharacterById(citizenid)
    return exports.qbx_core:GetPlayerByCitizenId(citizenid)
end

local function queryDatabaseProfiles(first, last)
    local result = MySQL.query.await("SELECT citizenid, charinfo, metadata FROM players")
    local profiles = {}
    for i = 1, #result do
        local item = result[i]
        local charinfo = type(item.charinfo) == "table" and item.charinfo or json.decode(item.charinfo) or {}
        local metadata = type(item.metadata) == "table" and item.metadata or json.decode(item.metadata) or {}
        local firstname = (charinfo.firstname or ""):lower()
        local lastname = (charinfo.lastname or ""):lower()

        if (first ~= "" and firstname:find(first)) or (last ~= "" and lastname:find(last)) then
            profiles[item.citizenid] = {
                firstName = charinfo.firstname,
                lastName = charinfo.lastname,
                dob = charinfo.birthdate,
                gender = charinfo.gender,
                phone = charinfo.phone or metadata.phone or nil,
                id = getPlayerSource(item.citizenid),
                img = metadata.img or nil,
                ethnicity = charinfo.nationality or metadata.ethnicity or "N/A"
            }
        end
    end
    return profiles
end

---@param src number
---@param first string|nil
---@param last string|nil
---@return table
function Bridge.nameSearch(src, first, last)
    local player = exports.qbx_core:GetPlayer(src)
    if not player or not config.policeAccess[player.PlayerData.job.name] then return false end

    local firstname = (first or ""):lower()
    local lastname = (last or ""):lower()
    local data = queryDatabaseProfiles(firstname, lastname)

    local profiles = {}
    for k, v in pairs(data) do
        profiles[k] = v
    end

    return profiles
end

---@param source number
---@param characterSearched string
---@return table
function Bridge.characterSearch(source, characterSearched)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not config.policeAccess[player.PlayerData.job.name] then return false end

    local result = MySQL.query.await("SELECT citizenid, charinfo, metadata FROM players WHERE citizenid = ?", {characterSearched})
    local item = result and result[1]
    if not item then return end

    local charinfo = type(item.charinfo) == "table" and item.charinfo or json.decode(item.charinfo) or {}
    local metadata = type(item.metadata) == "table" and item.metadata or json.decode(item.metadata) or {}

    local profiles = {}
    profiles[item.citizenid] = {
        firstName = charinfo.firstname,
        lastName = charinfo.lastname,
        dob = charinfo.birthdate,
        gender = charinfo.gender,
        phone = charinfo.phone or metadata.phone or nil,
        id = getPlayerSource(item.citizenid),
        img = metadata.img or nil,
        ethnicity = charinfo.nationality or metadata.ethnicity or "N/A"
    }
    return profiles
end

---@param src number
---@return table
function Bridge.getPlayerInfo(src)
    local player = exports.qbx_core:GetPlayer(src) or {}
    local charinfo = player.PlayerData and player.PlayerData.charinfo or {}
    local job = player.PlayerData and player.PlayerData.job or {}
    local metadata = player.PlayerData and player.PlayerData.metadata or {}
    return {
        firstName = charinfo.firstname or "",
        lastName = charinfo.lastname or "",
        job = job.name or "",
        jobLabel = job.label or "",
        callsign = metadata.callsign or "",
        img = metadata.img or "user.jpg",
        characterId = player.PlayerData and player.PlayerData.citizenid
    }
end

local function getVehicleCharacter(citizenid)
    local player = findCharacterById(citizenid)
    if player then
        return {
            firstName = player.PlayerData.charinfo.firstname,
            lastName = player.PlayerData.charinfo.lastname,
            characterId = player.PlayerData.citizenid
        }
    end
    local result = MySQL.query.await("SELECT citizenid, charinfo FROM players WHERE citizenid = ?", {citizenid})
    local item = result and result[1]
    if not item then return nil end
    local charinfo = type(item.charinfo) == "table" and item.charinfo or json.decode(item.charinfo) or {}
    return {
        firstName = charinfo.firstname,
        lastName = charinfo.lastname,
        characterId = item.citizenid
    }
end

local function queryDatabaseVehicles(find, findData)
    local query = ("SELECT * FROM player_vehicles WHERE %s = ?"):format(find)
    local result = MySQL.query.await(query, {findData})
    local vehicles = {}
    local character = find == "citizenid" and getVehicleCharacter(findData)

    for i = 1, #result do
        local item = result[i]
        if find == "plate" then character = getVehicleCharacter(item.citizenid) end
        local props = type(item.vehicle) == "table" and item.vehicle or json.decode(item.vehicle) or {}
        vehicles[item.plate] = {
            id = item.plate,
            color = props.color1,
            make = nil,
            model = props.model,
            plate = item.plate,
            class = nil,
            stolen = item.stolen == 1,
            character = character
        }
    end
    return vehicles
end

---@param src number
---@param searchBy string
---@param data number|string
---@return table
function Bridge.viewVehicles(src, searchBy, data)
    local player = exports.qbx_core:GetPlayer(src)
    if not player or not config.policeAccess[player.PlayerData.job.name] then return false end

    local vehicles = {}
    if searchBy == "plate" then
        local found = queryDatabaseVehicles("plate", data)
        for k, v in pairs(found) do vehicles[k] = v end
    elseif searchBy == "owner" then
        local found = queryDatabaseVehicles("citizenid", data)
        for k, v in pairs(found) do vehicles[k] = v end
    end
    return vehicles
end

---@param id string citizenid
---@return table
function Bridge.getProperties(id)
    return {}
end

---@param id string citizenid
---@return table
function Bridge.getLicenses(id)
    --[[ info in a license.
        {
            type = string (driver, weapon, hunting, etc),
            status = string (valid, expired, suspended, etc),
            issued = timestamp,
            expires = timestamp,
            identifier = in ND it's a 16 character identifier including letters and numbers.
        }
    ]]

    local result = MySQL.query.await("SELECT metadata FROM players WHERE citizenid = ?", {id})
    local metadata = result and result[1] and (type(result[1].metadata) == "table" and result[1].metadata or json.decode(result[1].metadata)) or {}
    return metadata.licenses or {}
end

---@param characterId string
---@param licenseIdentifier string
---@param newLicenseStatus string
function Bridge.editPlayerLicense(characterId, licenseIdentifier, newLicenseStatus)
    local player = findCharacterById(characterId)
    if player then
        local licenses = player.Functions.GetMetaData("licenses") or {}
        for _, lic in ipairs(licenses) do
            if lic.identifier == licenseIdentifier then
                lic.status = newLicenseStatus
                break
            end
        end
        player.Functions.SetMetaData("licenses", licenses)
        player.Functions.Save()
        return
    end

    local result = MySQL.query.await("SELECT metadata FROM players WHERE citizenid = ?", {characterId})
    if not result or not result[1] then return end
    local metadata = type(result[1].metadata) == "table" and result[1].metadata or json.decode(result[1].metadata) or {}
    local licenses = metadata.licenses or {}
    for _, lic in ipairs(licenses) do
        if lic.identifier == licenseIdentifier then
            lic.status = newLicenseStatus
            break
        end
    end
    metadata.licenses = licenses
    MySQL.update.await("UPDATE players SET metadata = ? WHERE citizenid = ?", {json.encode(metadata), characterId})
end

---@param characterId string
---@param fine number
function Bridge.createInvoice(characterId, fine)
    print("[^8WARNING^7] No Billing system configured for Qbox!")
    print("[^8WARNING^7] Go to: ^4@ND_MDT/bridge/qb/server.lua^7 to implement!")
end

---@param id string plate
---@param stolen boolean
---@param plate string
function Bridge.vehicleStolen(id, stolen, plate)
    MySQL.query("UPDATE player_vehicles SET stolen = ? WHERE plate = ?", {stolen and 1 or 0, id})
end

---@return table
function Bridge.getStolenVehicles()
    local plates = {}
    local result = MySQL.query.await("SELECT plate FROM player_vehicles WHERE stolen = 1")
    for i = 1, #result do
        plates[#plates+1] = result[i].plate
    end

    local bolos = MySQL.query.await("SELECT data FROM nd_mdt_bolos WHERE type = 'vehicle'")
    for i = 1, #bolos do
        local info = json.decode(bolos[i].data) or {}
        if info.plate then
            plates[#plates+1] = info.plate
        end
    end

    return plates
end

---@param characterId string citizenid
function Bridge.getPlayerImage(characterId)
    local player = findCharacterById(characterId)
    if player then
        return player.PlayerData.metadata and player.PlayerData.metadata.img
    end
    local result = MySQL.query.await("SELECT metadata FROM players WHERE citizenid = ?", {characterId})
    if not result or not result[1] then return nil end
    local metadata = type(result[1].metadata) == "table" and result[1].metadata or json.decode(result[1].metadata) or {}
    return metadata.img
end

---@param source number
---@param characterId string
---@param key any
---@param value any
function Bridge.updatePlayerMetadata(source, characterId, key, value)
    local player = exports.qbx_core:GetPlayer(source)
    if player then
        player.Functions.SetMetaData(key, value)
    end
end

function Bridge.getRecords(id)
    local result = MySQL.query.await("SELECT records FROM nd_mdt_records WHERE `character` = ? LIMIT 1", {id})
    if not result or not result[1] then
        return {}, false
    end
    return json.decode(result[1].records), true
end

local function filterEmployeeSearch(charinfo, metadata, search)
    local toSearch = ("%s %s %s"):format(
        (charinfo.firstname or ""):lower(),
        (charinfo.lastname or ""):lower(),
        (metadata.callsign and tostring(metadata.callsign) or ""):lower()
    )
    return toSearch:find(search:lower()) ~= nil
end

function Bridge.viewEmployees(src, search)
    local player = exports.qbx_core:GetPlayer(src)
    if not player or not config.policeAccess[player.PlayerData.job.name] then return end

    local employees = {}
    local onlinePlayers = exports.qbx_core:GetQBPlayers()
    local result = MySQL.query.await("SELECT citizenid, charinfo, job, metadata FROM players")

    for i = 1, #result do
        local info = result[i]
        local charinfo = type(info.charinfo) == "table" and info.charinfo or json.decode(info.charinfo) or {}
        local job = type(info.job) == "table" and info.job or json.decode(info.job) or {}

        if not config.policeAccess[job.name] then goto next end

        local metadata = {}
        local plySource = nil

        for src2, ply in pairs(onlinePlayers) do
            if ply.citizenid == info.citizenid then
                plySource = src2
                job = ply.job
                metadata = ply.metadata or {}
                charinfo = ply.charinfo or charinfo
                break
            end
        end

        if not plySource then
            metadata = type(info.metadata) == "table" and info.metadata or json.decode(info.metadata) or {}
        end

        if not filterEmployeeSearch(charinfo, metadata, search or "") then goto next end

        employees[#employees+1] = {
            source = plySource,
            charId = info.citizenid,
            first = charinfo.firstname,
            last = charinfo.lastname,
            img = metadata.img,
            callsign = metadata.callsign,
            job = job.name,
            jobInfo = {
                label = job.label,
                grade = job.grade,
                isboss = job.isboss,
            },
            dob = charinfo.birthdate,
            gender = charinfo.gender,
            phone = charinfo.phone or metadata.phone
        }

        ::next::
    end

    return employees
end

function Bridge.employeeUpdateCallsign(src, charid, callsign)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, "An issue occured try again later!"
    end

    if not tonumber(callsign) then
        return false, "Callsign must be a number!"
    end

    callsign = tostring(callsign)
    if not charid then
        return false, "Employee not found!"
    end

    local srcJob = player.PlayerData.job
    local srcGrade = srcJob.grade and srcJob.grade.level or 0
    local isAdmin = player.PlayerData.group == "admin" or player.PlayerData.group == "superadmin"

    local result = MySQL.query.await("SELECT citizenid, metadata FROM players")
    local targetMetadata = nil
    for i = 1, #result do
        local info = result[i]
        local metadata = type(info.metadata) == "table" and info.metadata or json.decode(info.metadata) or {}
        if metadata.callsign == callsign then
            return false, "This callsign is already used."
        end
        if info.citizenid == charid then
            targetMetadata = metadata
        end
    end

    local targetPlayer = findCharacterById(charid)
    if targetPlayer then
        local targetGrade = targetPlayer.PlayerData.job.grade and targetPlayer.PlayerData.job.grade.level or 0
        if not isAdmin and srcGrade <= targetGrade then
            return false, "You can only update lower rank employees!"
        end
        targetPlayer.Functions.SetMetaData("callsign", callsign)
        targetPlayer.Functions.Save()
        return callsign
    elseif not targetMetadata then
        return false, "Employee not found"
    end

    targetMetadata.callsign = callsign
    MySQL.update.await("UPDATE players SET metadata = ? WHERE citizenid = ?", {json.encode(targetMetadata), charid})
    return callsign
end

function Bridge.updateEmployeeRank(src, update)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, "An issue occured try again later!"
    end

    local isAdmin = player.PlayerData.group == "admin" or player.PlayerData.group == "superadmin"
    local srcGrade = player.PlayerData.job.grade and player.PlayerData.job.grade.level or 0

    if not isAdmin and srcGrade <= update.newRank then
        return false, "You can't set employees higher rank than you!"
    end

    local jobData = exports.qbx_core:GetJobs()[update.job]
    if not jobData then
        return false, "Job not found!"
    end

    local gradeLevel = tonumber(update.newRank)
    local gradeData = jobData.grades[gradeLevel]
    if not gradeData then
        return false, "Rank not found!"
    end

    local rankLabel = gradeData.name

    if not update.charid then
        return false, "Employee not found!"
    end

    local targetPlayer = findCharacterById(update.charid)
    if targetPlayer then
        local targetGrade = targetPlayer.PlayerData.job.grade and targetPlayer.PlayerData.job.grade.level or 0
        if not isAdmin and srcGrade <= targetGrade then
            return false, "You can only update lower rank employees!"
        end
        targetPlayer.Functions.SetJob(update.job, gradeLevel)
        return rankLabel
    end

    local result = MySQL.query.await("SELECT job FROM players WHERE citizenid = ?", {update.charid})
    if not result or not result[1] then
        return false, "Employee not found!"
    end

    local existingJob = type(result[1].job) == "table" and result[1].job or json.decode(result[1].job) or {}
    local existingGrade = existingJob.grade and existingJob.grade.level or 0

    if not isAdmin and srcGrade <= existingGrade then
        return false, "You can only update lower rank employees!"
    end

    local newJob = {
        name = update.job,
        label = jobData.label,
        payment = gradeData.payment or 0,
        onduty = existingJob.onduty or true,
        isboss = gradeData.isboss or false,
        grade = {
            name = gradeData.name,
            level = gradeLevel,
        },
    }

    MySQL.update.await("UPDATE players SET job = ? WHERE citizenid = ?", {json.encode(newJob), update.charid})
    return rankLabel
end

function Bridge.removeEmployeeJob(src, charid)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, "An issue occured try again later!"
    end

    if not charid then
        return false, "Employee not found!"
    end

    local isAdmin = player.PlayerData.group == "admin" or player.PlayerData.group == "superadmin"
    local srcGrade = player.PlayerData.job.grade and player.PlayerData.job.grade.level or 0

    local targetPlayer = findCharacterById(charid)
    if targetPlayer then
        local targetGrade = targetPlayer.PlayerData.job.grade and targetPlayer.PlayerData.job.grade.level or 0
        if not isAdmin and srcGrade <= targetGrade then
            return false, "You can only update lower rank employees!"
        end
        targetPlayer.Functions.SetJob("unemployed", 0)
        return true
    end

    local result = MySQL.query.await("SELECT job FROM players WHERE citizenid = ?", {charid})
    if not result or not result[1] then
        return false, "Employee not found"
    end

    local existingJob = type(result[1].job) == "table" and result[1].job or json.decode(result[1].job) or {}
    local existingGrade = existingJob.grade and existingJob.grade.level or 0

    if not isAdmin and srcGrade <= existingGrade then
        return false, "You can only update lower rank employees!"
    end

    local unemployedJob = {
        name = "unemployed",
        label = "Unemployed",
        payment = 10,
        onduty = true,
        isboss = false,
        grade = {
            name = "freelancer",
            level = 0,
        },
    }

    MySQL.update.await("UPDATE players SET job = ? WHERE citizenid = ?", {json.encode(unemployedJob), charid})
    return true
end

function Bridge.invitePlayerToJob(src, target)
    local player = exports.qbx_core:GetPlayer(src)
    if not player or not player.PlayerData.job.name then return end

    local targetPlayer = exports.qbx_core:GetPlayer(target)
    if not targetPlayer then return end

    targetPlayer.Functions.SetJob(player.PlayerData.job.name, 0)
    return true
end

function Bridge.ComparePlates(plate1, plate2)
    return plate1:gsub(" ", "") == plate2:gsub(" ", "")
end

lib.callback.register("ND_MDT:getRanks", function(src, jobName)
    local jobData = exports.qbx_core:GetJobs()[jobName]
    if not jobData then return nil end
    return jobData.grades
end)

return Bridge
