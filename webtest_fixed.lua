local component = require("component")
local event = require("event")
local computer = require("computer")

print("")
print("═══════════════════════════════════════════════════════════════")
print("  ТЕСТ1 ВЫДАЧИ NBT ПРЕДМЕТОВ ЧЕРЕЗ ME INTERFACE + PIM")
print("═══════════════════════════════════════════════════════════════")
print("")

-- 1. Проверяем компоненты
print("1. ПРОВЕРКА КОМПОНЕНТОВ")
print("")

-- ME интерфейс
if not component.isAvailable("me_interface") then
    print("❌ ME интерфейс НЕ ДОСТУПЕН!")
    return
end
local me = component.me_interface
print("✅ ME интерфейс доступен")

-- PIM
local pimAddr = nil
for addr in component.list("pim") do
    pimAddr = addr
    break
end
if not pimAddr then
    print("❌ PIM НЕ НАЙДЕН!")
    return
end
local pim = component.proxy(pimAddr)
print("✅ PIM найден: " .. pimAddr)

print("")
print("2. ВВОД ДАННЫХ")
print("")

io.write("  Internal name (например GraviSuite:vajra): ")
local internalName = io.read()
internalName = internalName:match("^%s*(.-)%s*$")

if not internalName or internalName == "" then
    print("   Используем GraviSuite:vajra")
    internalName = "GraviSuite:vajra"
end

io.write("  Damage (Enter для 0): ")
local dmgInput = io.read()
local damage = 0
if dmgInput and dmgInput ~= "" then
    damage = tonumber(dmgInput) or 0
end

io.write("  Количество (Enter для 1): ")
local qtyInput = io.read()
local testQty = 1
if qtyInput and qtyInput ~= "" then
    testQty = tonumber(qtyInput) or 1
end

print("")
print("   Тестируем: " .. internalName .. " (damage: " .. damage .. ") x" .. testQty)
print("")

-- 3. Проверяем наличие предмета в ME
print("3. ПОИСК В ME")
print("")

local fingerprint = { id = internalName, dmg = damage }
local items = me.getItemsInNetwork()
local foundItem = nil

for _, item in ipairs(items) do
    if item.name == internalName and (item.damage or 0) == damage then
        foundItem = item
        break
    end
end

if not foundItem then
    print("❌ Предмет НЕ НАЙДЕН в ME системе!")
    print("")
    print("   Похожие предметы в ME:")
    local count = 0
    for _, item in ipairs(items) do
        if string.find(item.name, internalName:match("[^:]+$") or "") then
            count = count + 1
            if count <= 10 then
                print("     " .. item.name .. " (damage: " .. (item.damage or 0) .. ") - " .. (item.size or 0) .. " шт.")
            end
        end
    end
    if count == 0 then
        print("     Нет похожих предметов.")
    end
    return
end

print("✅ Предмет найден!")
print("   Количество в ME: " .. (foundItem.size or 0) .. " шт.")

if (foundItem.size or 0) < testQty then
    print("⚠️ В ME меньше предметов чем нужно!")
    testQty = foundItem.size or 0
    if testQty == 0 then
        print("❌ Нет предметов для теста")
        return
    end
    print("   Тестируем с " .. testQty .. " шт.")
end

print("")
print("4. ПРОВЕРКА ИНВЕНТАРЯ PIM")
print("")

local freeSlots = 0
for slot = 1, 36 do
    local stack = pim.getStackInSlot(slot)
    if not stack or not stack.size or stack.size == 0 then
        freeSlots = freeSlots + 1
    end
end

print("   Свободных слотов в PIM: " .. freeSlots)

if freeSlots == 0 then
    print("❌ ИНВЕНТАРЬ ПОЛОН! Освободите место.")
    print("   Нажмите любую клавишу для выхода...")
    event.pull("key_down")
    return
end

print("")
print("5. ТЕСТОВАЯ ВЫДАЧА ЧЕРЕЗ ME INTERFACE")
print("")

-- Пробуем все направления (1-7)
-- 1=DOWN, 2=UP, 3=NORTH, 4=SOUTH, 5=WEST, 6=EAST, 7=UNKNOWN
local directions = {
    {code = 1, name = "DOWN"},
    {code = 2, name = "UP"},
    {code = 3, name = "NORTH"},
    {code = 4, name = "SOUTH"},
    {code = 5, name = "WEST"},
    {code = 6, name = "EAST"},
    {code = 7, name = "UNKNOWN"},
}

local successDirection = nil
local extracted = 0

print("   🔍 Пробуем exportItem с разными направлениями:")
print("")

for _, dir in ipairs(directions) do
    if extracted == 0 then
        print("   Пробуем направление: " .. dir.name .. " (код: " .. dir.code .. ")")
        
        local success, result = pcall(function()
            return me.exportItem(fingerprint, dir.code, testQty)
        end)
        
        if success then
            if result and type(result) == "number" and result > 0 then
                print("   ✅ УСПЕШНО! Выдано " .. result .. " шт. в направлении " .. dir.name)
                extracted = result
                successDirection = dir.name
            else
                print("     ❌ Результат: " .. tostring(result))
            end
        else
            print("     ⚠️ Ошибка: " .. tostring(result))
        end
    end
end

-- Если не сработало через exportItem, пробуем другие методы
if extracted == 0 then
    print("")
    print("   🔍 Пробуем альтернативные методы:")
    print("")
    
    -- Метод 1: через exportItem с другим форматом
    print("   1. exportItem с форматом {id=..., dmg=...}:")
    local success, result = pcall(function()
        return me.exportItem({id = internalName, dmg = damage}, 2, testQty)
    end)
    if success and result and result > 0 then
        print("   ✅ УСПЕШНО! Выдано " .. result .. " шт.")
        extracted = result
        successDirection = "UP (альтернативный)"
    else
        print("     ❌ " .. tostring(result))
    end
    
    -- Метод 2: через pushItem в PIM напрямую
    if extracted == 0 then
        print("")
        print("   2. Прямая отправка в PIM (pushItem):")
        -- Сначала пробуем выдать в ME интерфейс
        local ok, items = pcall(function()
            return me.getItemsInNetwork()
        end)
        
        if ok and items then
            for _, item in ipairs(items) do
                if item.name == internalName and (item.damage or 0) == damage then
                    local success, result = pcall(function()
                        return pim.pushItem(PIM_DIRECTION, 1, item.size)
                    end)
                    if success and result and result > 0 then
                        print("   ✅ УСПЕШНО! Отправлено " .. result .. " шт. в PIM")
                        extracted = result
                        successDirection = "pushItem"
                    else
                        print("     ❌ " .. tostring(result))
                    end
                    break
                end
            end
        end
    end
end

-- Если ничего не сработало
if extracted == 0 then
    print("")
    print("❌ НИ ОДИН СПОСОБ НЕ СРАБОТАЛ!")
    print("")
    print("📋 ВОЗМОЖНЫЕ ПРИЧИНЫ:")
    print("  1. NBT предметы не могут быть выданы через PIM")
    print("  2. PIM не правильно подключён к ME сети")
    print("  3. Нет кабеля между ME интерфейсом и PIM")
    print("")
    print("⚙️ РЕШЕНИЕ:")
    print("  1. Используй ME интерфейс + сундук для NBT предметов")
    print("  2. Поставь сундук за ME интерфейсом (невидимый для игрока)")
    print("  3. В сундук выдавай предмет, потом забирай в PIM")
    print("")
    print("Нажмите любую клавишу для выхода...")
    event.pull("key_down")
    return
end

-- Если успешно
print("")
print("═══════════════════════════════════════════════════════════════")
print("  ✅ ТЕСТ ЗАВЕРШЁН УСПЕШНО!")
print("═══════════════════════════════════════════════════════════════")
print("")
print("✅ РАБОТАЮЩЕЕ НАПРАВЛЕНИЕ: " .. successDirection)
print("✅ ВЫДАНО: " .. extracted .. " шт.")
print("")

-- Проверяем инвентарь PIM
print("ПРОВЕРКА ИНВЕНТАРЯ PIM ПОСЛЕ ВЫДАЧИ:")
local hasItemsAfter = false
for slot = 1, 36 do
    local stack = pim.getStackInSlot(slot)
    if stack and stack.size and stack.size > 0 then
        hasItemsAfter = true
        print("  Слот " .. slot .. ": " .. stack.name .. " x" .. stack.size)
    end
end

if not hasItemsAfter then
    print("  ⚠️ Инвентарь пуст! Предмет не появился в PIM.")
else
    print("  ✅ Предмет успешно появился в инвентаре PIM!")
end

print("")
print("═══════════════════════════════════════════════════════════════")
print("  КОД ДЛЯ ИСПОЛЬЗОВАНИЯ В ОСНОВНОМ СКРИПТЕ:")
print("═══════════════════════════════════════════════════════════════")
print("")
if successDirection == "pushItem" then
    print("  -- Через прямой push в PIM")
    print("  pim.pushItem(direction, slot, count)")
else
    print("  -- Через ME интерфейс")
    print("  local me = component.me_interface")
    print("  local fingerprint = { id = '" .. internalName .. "', dmg = " .. damage .. " }")
    print("  me.exportItem(fingerprint, " .. dirCode .. ", count)")
    print("  -- Где " .. dirCode .. " = " .. successDirection)
end
print("")
print("Нажмите любую клавишу для выхода...")
event.pull("key_down")
