-- ============================================================
-- ТЕСТ ВЫДАЧИ ЧЕРЕЗ PIM (ОДНА ПОПЫТКА, БЕЗ ЦИКЛОВ)
-- ============================================================

local component = require("component")

function findPIM()
    for addr in component.list("pim") do
        return addr
    end
    return nil
end

function findME()
    for addr in component.list("me_interface") do
        return component.proxy(addr)
    end
    return nil
end

-- ============================================================
-- ВЫДАЧА ОДНОЙ ПОПЫТКОЙ
-- ============================================================

function giveOnce(itemId, qty, damage)
    print("\n🧪 ВЫДАЧА: " .. itemId .. " x" .. qty)
    print("═" .. string.rep("═", 50))
    
    local pimAddr = findPIM()
    if not pimAddr then
        print("❌ PIM не найден!")
        return
    end
    
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return
    end
    
    -- Проверяем наличие в ME
    local items = me.getItemsInNetwork()
    local available = 0
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == (damage or 0) then
            available = available + (item.size or 0)
        end
    end
    
    if available == 0 then
        print("❌ Предмет не найден в ME!")
        print("\n💡 Доступные предметы:")
        for _, item in ipairs(items) do
            print("  " .. item.name .. " x" .. (item.size or 0))
        end
        return
    end
    
    print("✅ В ME есть: " .. available .. " шт.")
    
    -- Проверяем свободный слот
    local freeSlot = nil
    for slot = 1, 36 do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if not stack or (stack.size or stack.qty or 0) == 0 then
            freeSlot = slot
            break
        end
    end
    
    if not freeSlot then
        print("❌ Нет свободных слотов в инвентаре!")
        return
    end
    
    print("✅ Свободный слот: " .. freeSlot)
    
    -- ОДНА попытка выдачи
    local toTake = math.min(qty, 64)
    local fingerprint = { id = itemId, dmg = damage or 0 }
    
    print("⏳ Выдача " .. toTake .. " шт...")
    
    local success, result = pcall(function()
        return me.exportItem(fingerprint, "down", toTake)
    end)
    
    if success then
        if type(result) == "number" and result > 0 then
            print("✅ УСПЕШНО! Выдано: " .. result .. " шт.")
            
            -- Проверяем что попало в инвентарь
            local stack = component.invoke(pimAddr, "getStackInSlot", freeSlot)
            if stack then
                local name = stack.displayName or stack.label or stack.name or "?"
                local size = stack.size or stack.qty or 0
                local hasNBT = (stack.nbt or stack.tag) and " [ЕСТЬ NBT]" or ""
                print("  В слоте " .. freeSlot .. ": " .. name .. " x" .. size .. hasNBT)
            end
        elseif type(result) == "boolean" and result == true then
            print("✅ УСПЕШНО! Выдано: " .. toTake .. " шт.")
        else
            print("❌ НЕ УДАЛОСЬ! Ответ: " .. tostring(result))
            print("  Возможно предмет имеет NBT и не выдается через PIM напрямую")
        end
    else
        print("❌ ОШИБКА: " .. tostring(result))
    end
end

-- ============================================================
-- ПОКАЗАТЬ ME
-- ============================================================

function showME()
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return
    end
    
    print("\n📦 СОДЕРЖИМОЕ ME:")
    print("═" .. string.rep("═", 50))
    
    local items = me.getItemsInNetwork()
    local groups = {}
    
    for _, item in ipairs(items) do
        local key = item.name .. ":" .. (item.damage or 0)
        if not groups[key] then
            groups[key] = {
                name = item.name,
                damage = item.damage or 0,
                count = 0,
                hasNBT = false
            }
        end
        groups[key].count = groups[key].count + (item.size or 0)
        if item.nbt or item.tag then
            groups[key].hasNBT = true
        end
    end
    
    for key, data in pairs(groups) do
        local nbt = data.hasNBT and " [NBT]" or ""
        print(string.format("  %s (damage: %d) x%d%s", 
            data.name, data.damage, data.count, nbt))
    end
end

-- ============================================================
-- ОЧИСТИТЬ ИНВЕНТАРЬ
-- ============================================================

function clearInventory()
    local pimAddr = findPIM()
    if not pimAddr then
        print("❌ PIM не найден!")
        return
    end
    
    print("\n🗑️ ОЧИСТКА ИНВЕНТАРЯ")
    print("═" .. string.rep("═", 50))
    
    local count = 0
    for slot = 1, 36 do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack and (stack.size or stack.qty or 0) > 0 then
            component.invoke(pimAddr, "pushItem", "down", slot, 999)
            count = count + 1
        end
    end
    
    print("✅ Очищено слотов: " .. count)
end

-- ============================================================
-- ГЛАВНОЕ МЕНЮ
-- ============================================================

function main()
    print("\n" .. string.rep("═", 50))
    print("🧪 ТЕСТ ВЫДАЧИ ЧЕРЕЗ PIM")
    print(string.rep("═", 50))
    
    while true do
        print("\nВыберите действие:")
        print("  [1] Показать что в ME")
        print("  [2] Выдать предмет (ОДНА попытка)")
        print("  [3] Очистить инвентарь")
        print("  [Q] Выход")
        
        local choice = io.read()
        
        if choice == "1" then
            showME()
            
        elseif choice == "2" then
            print("\nВведите ID предмета (например: diamond_sword):")
            local itemId = io.read()
            if not itemId or itemId == "" then
                print("❌ Отменено")
                goto continue
            end
            
            if not itemId:find(":") then
                itemId = "minecraft:" .. itemId
            end
            
            print("Введите количество (1-64):")
            local qty = tonumber(io.read()) or 1
            if qty > 64 then qty = 64 end
            
            print("Введите damage (0 если не знаете):")
            local damage = tonumber(io.read()) or 0
            
            giveOnce(itemId, qty, damage)
            
        elseif choice == "3" then
            clearInventory()
            
        elseif choice == "q" or choice == "Q" then
            print("\n👋 Выход...")
            break
        end
        
        ::continue::
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================

local ok, err = pcall(main)
if not ok then
    print("\n❌ ОШИБКА:")
    print("  " .. tostring(err))
    print(debug.traceback())
end
