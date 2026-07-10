-- ============================================================
-- ТЕСТ ВЫДАЧИ С ДИАГНОСТИКОЙ NBT15
-- ============================================================

local component = require("component")
local serialization = require("serialization")

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
-- ПОКАЗАТЬ ДЕТАЛЬНУЮ ИНФОРМАЦИЮ О ПРЕДМЕТЕ
-- ============================================================

function showItemDetails(itemId, damage)
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return
    end
    
    print("\n🔍 ДЕТАЛЬНАЯ ИНФОРМАЦИЯ О ПРЕДМЕТЕ")
    print("═" .. string.rep("═", 50))
    
    local items = me.getItemsInNetwork()
    local found = false
    
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == (damage or 0) then
            found = true
            print("\n📦 Найден предмет:")
            print("  Имя: " .. (item.name or "?"))
            print("  DisplayName: " .. (item.displayName or "нет"))
            print("  Label: " .. (item.label or "нет"))
            print("  Damage: " .. (item.damage or 0))
            print("  Количество: " .. (item.size or 0))
            print("  MaxSize: " .. (item.maxSize or 64))
            
            -- Показываем NBT
            local nbt = item.nbt or item.tag
            if nbt then
                print("\n  📋 ЕСТЬ NBT-ДАННЫЕ:")
                if type(nbt) == "table" then
                    for k, v in pairs(nbt) do
                        if type(v) == "table" then
                            print("    " .. k .. ": (таблица)")
                            for k2, v2 in pairs(v) do
                                print("      " .. k2 .. ": " .. tostring(v2))
                            end
                        else
                            print("    " .. k .. ": " .. tostring(v))
                        end
                    end
                else
                    print("    " .. tostring(nbt))
                end
            else
                print("\n  ❌ NBT-данных НЕТ")
            end
            
            -- Показываем полный объект
            print("\n  📄 Полный объект:")
            print("  " .. serialization.serialize(item))
        end
    end
    
    if not found then
        print("❌ Предмет не найден в ME!")
    end
end

-- ============================================================
-- ВЫДАЧА С ДИАГНОСТИКОЙ
-- ============================================================

function giveWithDiagnostic(itemId, qty, damage)
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
    
    -- Проверяем наличие
    local items = me.getItemsInNetwork()
    local available = 0
    local itemData = nil
    
    for _, item in ipairs(items) do
        if item.name == itemId and (item.damage or 0) == (damage or 0) then
            available = available + (item.size or 0)
            itemData = item
        end
    end
    
    if available == 0 then
        print("❌ Предмет не найден в ME!")
        print("\n💡 Попробуйте один из этих ID:")
        local shown = 0
        for _, item in ipairs(items) do
            if shown < 20 then
                print("  " .. item.name .. " x" .. (item.size or 0))
                shown = shown + 1
            end
        end
        return
    end
    
    print("✅ В ME есть: " .. available .. " шт.")
    
    -- Показываем NBT
    if itemData and (itemData.nbt or itemData.tag) then
        print("⚠️ У предмета ЕСТЬ NBT-данные!")
        print("  Возможно, поэтому PIM не может его выдать.")
        print("  Попробуйте использовать сундук-буфер.")
    end
    
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
    
    -- ПРОБУЕМ РАЗНЫЕ СПОСОБЫ
    local toTake = math.min(qty, 64)
    
    -- Способ 1: Стандартный
    print("\n📌 Способ 1: Стандартная выдача")
    local fingerprint = { id = itemId, dmg = damage or 0 }
    
    local success, result = pcall(function()
        return me.exportItem(fingerprint, "down", toTake)
    end)
    
    if success and result and result > 0 then
        print("✅ УСПЕШНО! Выдано: " .. result .. " шт.")
        return
    else
        print("❌ Не удалось. Ответ: " .. tostring(result))
    end
    
    -- Способ 2: Без damage
    print("\n📌 Способ 2: Без damage")
    local fingerprint2 = { id = itemId }
    
    local success2, result2 = pcall(function()
        return me.exportItem(fingerprint2, "down", toTake)
    end)
    
    if success2 and result2 and result2 > 0 then
        print("✅ УСПЕШНО! Выдано: " .. result2 .. " шт.")
        return
    else
        print("❌ Не удалось. Ответ: " .. tostring(result2))
    end
    
    -- Способ 3: С NBT (если есть)
    if itemData and (itemData.nbt or itemData.tag) then
        print("\n📌 Способ 3: С NBT-данными")
        local fingerprint3 = { 
            id = itemId, 
            dmg = damage or 0,
            nbt = itemData.nbt or itemData.tag 
        }
        
        local success3, result3 = pcall(function()
            return me.exportItem(fingerprint3, "down", toTake)
        end)
        
        if success3 and result3 and result3 > 0 then
            print("✅ УСПЕШНО! Выдано: " .. result3 .. " шт.")
            return
        else
            print("❌ Не удалось. Ответ: " .. tostring(result3))
        end
    end
    
    -- ВСЁ НЕ УДАЛОСЬ
    print("\n❌ ВСЕ СПОСОБЫ НЕ УДАЛИСЬ!")
    print("  Предмет имеет NBT и не выдается через PIM напрямую.")
    print("  Нужно использовать СУНДУК-БУФЕР.")
    
    -- Предлагаем показать детали
    print("\nПоказать детальную информацию о предмете? (y/n):")
    local show = io.read()
    if show == "y" or show == "Y" then
        showItemDetails(itemId, damage)
    end
end

-- ============================================================
-- ПОКАЗАТЬ ВСЕ ПРЕДМЕТЫ В ME
-- ============================================================

function showAllItems()
    local me = findME()
    if not me then
        print("❌ ME не найден!")
        return
    end
    
    print("\n📦 ВСЕ ПРЕДМЕТЫ В ME:")
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
                hasNBT = false,
                maxSize = item.maxSize or 64
            }
        end
        groups[key].count = groups[key].count + (item.size or 0)
        if item.nbt or item.tag then
            groups[key].hasNBT = true
        end
    end
    
    local i = 0
    for key, data in pairs(groups) do
        i = i + 1
        local nbt = data.hasNBT and " [ЕСТЬ NBT]" or ""
        local sizeInfo = ""
        if data.maxSize and data.maxSize < 64 then
            sizeInfo = " (max: " .. data.maxSize .. ")"
        end
        print(string.format("  %d. %s (damage: %d) x%d%s%s", 
            i, data.name, data.damage, data.count, nbt, sizeInfo))
    end
    
    print("\nВсего групп: " .. i)
end

-- ============================================================
-- ГЛАВНОЕ МЕНЮ
-- ============================================================

function main()
    print("\n" .. string.rep("═", 50))
    print("🧪 ТЕСТ ВЫДАЧИ С ДИАГНОСТИКОЙ NBT")
    print(string.rep("═", 50))
    
    while true do
        print("\nВыберите действие:")
        print("  [1] Показать все предметы в ME")
        print("  [2] Выдать предмет (с диагностикой)")
        print("  [3] Показать детали предмета")
        print("  [4] Очистить инвентарь")
        print("  [Q] Выход")
        
        local choice = io.read()
        
        if choice == "1" then
            showAllItems()
            
        elseif choice == "2" then
            print("\nВведите ID предмета (например: GraviSuite:vajra):")
            local itemId = io.read()
            if not itemId or itemId == "" then
                print("❌ Отменено")
                goto continue
            end
            
            print("Введите количество (1-64):")
            local qty = tonumber(io.read()) or 1
            if qty > 64 then qty = 64 end
            
            print("Введите damage (0 если не знаете):")
            local damage = tonumber(io.read()) or 0
            
            giveWithDiagnostic(itemId, qty, damage)
            
        elseif choice == "3" then
            print("\nВведите ID предмета:")
            local itemId = io.read()
            if not itemId or itemId == "" then
                print("❌ Отменено")
                goto continue
            end
            
            print("Введите damage (0 если не знаете):")
            local damage = tonumber(io.read()) or 0
            
            showItemDetails(itemId, damage)
            
        elseif choice == "4" then
            local pimAddr = findPIM()
            if not pimAddr then
                print("❌ PIM не найден!")
                goto continue
            end
            
            print("⚠️ Очистить инвентарь? (y/n):")
            local confirm = io.read()
            if confirm == "y" or confirm == "Y" then
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
