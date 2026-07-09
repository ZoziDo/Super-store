-- ============================================================
-- ★★★ ПОЛНАЯ ДИАГНОСТИКА ME + PIM ★★★1111
-- Сохраните как /home/diag_full.lua
-- Запустите: lua /home/diag_full.lua
-- ============================================================

local component = require("component")
local event = require("event")
local serialization = require("serialization")

print("")
print("═══════════════════════════════════════════════════════════════")
print("  ПОЛНАЯ ДИАГНОСТИКА ME + PIM")
print("═══════════════════════════════════════════════════════════════")
print("")

-- ============================================================
-- 1. ПРОВЕРКА КОМПОНЕНТОВ
-- ============================================================
print("1. ПРОВЕРКА КОМПОНЕНТОВ")
print("")

-- Все компоненты
print("Все доступные компоненты:")
for addr, type in component.list() do
    if type == "me_interface" or type == "pim" or type == "inventory" then
        print("  " .. type .. " -> " .. addr)
    end
end
print("")

-- ME интерфейс
if not component.isAvailable("me_interface") then
    print("❌ ME интерфейс НЕ ДОСТУПЕН!")
    return
end
local me = component.me_interface
print("✅ ME интерфейс доступен")

-- Проверяем методы ME интерфейса
print("")
print("Доступные методы ME интерфейса:")
for k, v in pairs(me) do
    if type(v) == "function" then
        print("  " .. k)
    end
end
print("")

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

-- Проверяем методы PIM
print("")
print("Доступные методы PIM:")
for k, v in pairs(pim) do
    if type(v) == "function" then
        print("  " .. k)
    end
end
print("")

-- ============================================================
-- 2. ПРОВЕРКА ИНВЕНТАРЯ PIM
-- ============================================================
print("2. ПРОВЕРКА ИНВЕНТАРЯ PIM")
print("")

local freeSlots = 0
local hasItems = false

for slot = 1, 36 do
    local success, stack = pcall(function()
        return pim.getStackInSlot(slot)
    end)
    if success and stack and stack.size and stack.size > 0 then
        hasItems = true
        print("  Слот " .. slot .. ": " .. stack.name .. " x" .. stack.size)
    else
        freeSlots = freeSlots + 1
    end
end

print("")
print("  Свободных слотов: " .. freeSlots)
if freeSlots == 0 then
    print("❌ ИНВЕНТАРЬ ПОЛОН! Освободите место.")
end
print("")

-- ============================================================
-- 3. ВВОД ДАННЫХ
-- ============================================================
print("3. ВВОД ДАННЫХ")
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
print("  Тестируем: " .. internalName .. " (damage: " .. damage .. ") x" .. testQty)
print("")

-- ============================================================
-- 4. ПОИСК В ME
-- ============================================================
print("4. ПОИСК В ME")
print("")

local fingerprint = { id = internalName, dmg = damage }

-- Получаем все предметы
local items = me.getItemsInNetwork()
print("  Всего предметов в ME: " .. #items)
print("")

-- Ищем точное совпадение
local foundItem = nil
local exactMatches = {}

for _, item in ipairs(items) do
    if item.name == internalName and (item.damage or 0) == damage then
        table.insert(exactMatches, item)
    end
end

if #exactMatches > 0 then
    foundItem = exactMatches[1]
    print("  ✅ Найдено точных совпадений: " .. #exactMatches)
    print("  Имя: " .. foundItem.name)
    print("  Damage: " .. (foundItem.damage or 0))
    print("  Количество: " .. (foundItem.size or 0))
else
    print("  ❌ Точных совпадений НЕТ!")
    print("")
    print("  Похожие предметы в ME:")
    local count = 0
    for _, item in ipairs(items) do
        if string.find(item.name, internalName:match("[^:]+$") or "") then
            count = count + 1
            if count <= 20 then
                print("    " .. item.name .. " (damage: " .. (item.damage or 0) .. ") - " .. (item.size or 0) .. " шт.")
            end
        end
    end
    if count == 0 then
        print("    Нет похожих предметов!")
        print("")
        print("  Первые 20 предметов в ME:")
        for i = 1, math.min(20, #items) do
            local item = items[i]
            print("    " .. i .. ". " .. item.name .. " (damage: " .. (item.damage or 0) .. ") - " .. (item.size or 0) .. " шт.")
        end
    end
    print("")
    print("  Нажмите любую клавишу для выхода...")
    event.pull("key_down")
    return
end

if (foundItem.size or 0) < testQty then
    print("  ⚠️ В ME меньше предметов чем нужно для теста!")
    testQty = foundItem.size or 0
    if testQty == 0 then
        print("  ❌ Нет предметов для теста")
        print("  Нажмите любую клавишу для выхода...")
        event.pull("key_down")
        return
    end
    print("  Будем тестировать с " .. testQty .. " шт.")
end
print("")

-- ============================================================
-- 5. ПРОВЕРКА МЕТОДОВ ВЫДАЧИ (ПОЛНАЯ)
-- ============================================================
print("5. ПРОВЕРКА МЕТОДОВ ВЫДАЧИ")
print("")

local testResults = {}

-- Метод 1: exportItem с направлением "up"
print("  Метод 1: exportItem(fingerprint, \"up\", " .. testQty .. ")")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "up", testQty)
end)
if success then
    print("    Результат: " .. tostring(result))
    if result and type(result) == "number" and result > 0 then
        print("    ✅ РАБОТАЕТ! Выдано " .. result .. " шт.")
        table.insert(testResults, {method = "up", result = result})
    else
        print("    ❌ НЕ РАБОТАЕТ (вернул " .. tostring(result) .. ")")
    end
else
    print("    ❌ ОШИБКА: " .. tostring(result))
end
print("")

-- Метод 2: exportItem с направлением "down"
print("  Метод 2: exportItem(fingerprint, \"down\", " .. testQty .. ")")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "down", testQty)
end)
if success then
    print("    Результат: " .. tostring(result))
    if result and type(result) == "number" and result > 0 then
        print("    ✅ РАБОТАЕТ! Выдано " .. result .. " шт.")
        table.insert(testResults, {method = "down", result = result})
    else
        print("    ❌ НЕ РАБОТАЕТ (вернул " .. tostring(result) .. ")")
    end
else
    print("    ❌ ОШИБКА: " .. tostring(result))
end
print("")

-- Метод 3: exportItem с направлением "north"
print("  Метод 3: exportItem(fingerprint, \"north\", " .. testQty .. ")")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "north", testQty)
end)
if success then
    print("    Результат: " .. tostring(result))
    if result and type(result) == "number" and result > 0 then
        print("    ✅ РАБОТАЕТ! Выдано " .. result .. " шт.")
        table.insert(testResults, {method = "north", result = result})
    else
        print("    ❌ НЕ РАБОТАЕТ (вернул " .. tostring(result) .. ")")
    end
else
    print("    ❌ ОШИБКА: " .. tostring(result))
end
print("")

-- Метод 4: exportItem с направлением "south"
print("  Метод 4: exportItem(fingerprint, \"south\", " .. testQty .. ")")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "south", testQty)
end)
if success then
    print("    Результат: " .. tostring(result))
    if result and type(result) == "number" and result > 0 then
        print("    ✅ РАБОТАЕТ! Выдано " .. result .. " шт.")
        table.insert(testResults, {method = "south", result = result})
    else
        print("    ❌ НЕ РАБОТАЕТ (вернул " .. tostring(result) .. ")")
    end
else
    print("    ❌ ОШИБКА: " .. tostring(result))
end
print("")

-- Метод 5: exportItem с направлением "west"
print("  Метод 5: exportItem(fingerprint, \"west\", " .. testQty .. ")")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "west", testQty)
end)
if success then
    print("    Результат: " .. tostring(result))
    if result and type(result) == "number" and result > 0 then
        print("    ✅ РАБОТАЕТ! Выдано " .. result .. " шт.")
        table.insert(testResults, {method = "west", result = result})
    else
        print("    ❌ НЕ РАБОТАЕТ (вернул " .. tostring(result) .. ")")
    end
else
    print("    ❌ ОШИБКА: " .. tostring(result))
end
print("")

-- Метод 6: exportItem с направлением "east"
print("  Метод 6: exportItem(fingerprint, \"east\", " .. testQty .. ")")
local success, result = pcall(function()
    return me.exportItem(fingerprint, "east", testQty)
end)
if success then
    print("    Результат: " .. tostring(result))
    if result and type(result) == "number" and result > 0 then
        print("    ✅ РАБОТАЕТ! Выдано " .. result .. " шт.")
        table.insert(testResults, {method = "east", result = result})
    else
        print("    ❌ НЕ РАБОТАЕТ (вернул " .. tostring(result) .. ")")
    end
else
    print("    ❌ ОШИБКА: " .. tostring(result))
end
print("")

-- ============================================================
-- 6. ЕСЛИ НИЧЕГО НЕ РАБОТАЕТ - ДОПОЛНИТЕЛЬНЫЕ ПРОВЕРКИ
-- ============================================================
if #testResults == 0 then
    print("6. ДОПОЛНИТЕЛЬНЫЕ ПРОВЕРКИ")
    print("")
    
    -- Проверяем, есть ли предмет в ME через findItem (если доступен)
    if me.findItem then
        print("  Проверка через findItem:")
        local success, result = pcall(function()
            return me.findItem(fingerprint)
        end)
        if success and result then
            print("    Найдено: " .. tostring(result.size or 0) .. " шт.")
        else
            print("    Ошибка: " .. tostring(result))
        end
        print("")
    end
    
    -- Проверяем simulateExport (если доступен)
    if me.simulateExport then
        print("  Проверка через simulateExport:")
        local success, result = pcall(function()
            return me.simulateExport(fingerprint, "up", 1)
        end)
        if success and result then
            print("    Можно выдать: " .. tostring(result.size or 0) .. " шт.")
        else
            print("    Ошибка: " .. tostring(result))
        end
        print("")
    end
    
    -- Проверяем exportItem с другими параметрами
    print("  Проверка exportItem с разными вариантами:")
    
    -- Вариант: exportItem с 4 параметрами (force)
    local success, result = pcall(function()
        return me.exportItem(fingerprint, "up", 1, false)
    end)
    print("    exportItem(fingerprint, \"up\", 1, false) -> " .. tostring(result))
    
    local success, result = pcall(function()
        return me.exportItem(fingerprint, "up", 1, true)
    end)
    print("    exportItem(fingerprint, \"up\", 1, true) -> " .. tostring(result))
    print("")
    
    -- Проверяем, может проблема в том, что предмет с NBT
    print("  Проверка NBT:")
    local success, result = pcall(function()
        return me.getItemDetail(internalName, damage)
    end)
    if success and result then
        print("    displayName: " .. (result.displayName or "?"))
        print("    hasNBT: " .. tostring(result.hasNBT or false))
        if result.hasNBT then
            print("    ⚠️ У предмета есть NBT данные! Это может мешать.")
        end
    else
        print("    Не удалось получить детали: " .. tostring(result))
    end
    print("")
    
    print("❌ НИ ОДИН МЕТОД НЕ СРАБОТАЛ!")
    print("")
    print("ВОЗМОЖНЫЕ ПРИЧИНЫ:")
    print("  1. ME интерфейс НЕ ПОДКЛЮЧЁН к сети хранения")
    print("     - Проверь, светится ли ME интерфейс")
    print("     - Проверь, есть ли энергия в сети")
    print("  2. Рядом с ME интерфейсом НЕТ ИНВЕНТАРЯ")
    print("     - Нужен сундук/ящик в направлении выдачи")
    print("  3. PIM НЕ НАСТРОЕН на приём предметов")
    print("  4. Предмет имеет NBT данные (зачарования и т.д.)")
    print("")
    print("ЧТО ДЕЛАТЬ:")
    print("  1. Поставь сундук СВЕРХУ или СНИЗУ от ME интерфейса")
    print("  2. Проверь, что ME интерфейс подключён к сети")
    print("  3. Попробуй другой предмет (например minecraft:dirt)")
    print("")
    print("Нажми любую клавишу для выхода...")
    event.pull("key_down")
    return
end

-- ============================================================
-- 7. РЕЗУЛЬТАТЫ
-- ============================================================
print("7. РЕЗУЛЬТАТЫ")
print("")

print("  ✅ НАЙДЕНЫ РАБОЧИЕ МЕТОДЫ:")
for _, res in ipairs(testResults) do
    print("    - Направление \"" .. res.method .. "\" выдало " .. res.result .. " шт.")
end
print("")
print("  ИСПОЛЬЗУЙ В КОДЕ:")
print("    PULL_DIRECTION = \"" .. testResults[1].method .. "\"")
print("")

print("═══════════════════════════════════════════════════════════════")
print("  ✅ ДИАГНОСТИКА ЗАВЕРШЕНА")
print("═══════════════════════════════════════════════════════════════")
print("")

print("Нажми любую клавишу для выхода...")
event.pull("key_down")
