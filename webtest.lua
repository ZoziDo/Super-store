-- ============================================
-- ТЕСТОВЫЙ ВЕБ-СЕРВЕР ДЛЯ PIM MARKET
-- Сохраните как: /home/webtest.lua
-- ============================================

local component = require("component")
local computer = require("computer")
local internet = require("internet")
local serialization = require("serialization")
local event = require("event")

print("=" .. string.rep("=", 40))
print("ТЕСТОВЫЙ ВЕБ-СЕРВЕР PIM MARKET")
print("=" .. string.rep("=", 40))

-- Проверяем наличие internet компонента
if not component.isAvailable("internet") then
    print("ОШИБКА: Нет internet компонента!")
    print("Нужна интернет-карта в компьютере")
    return
end

-- Тестовые данные
local testPlayers = {
    ["ZoziDo"] = {
        balance = 1500.50,
        emaBalance = 300.25,
        transactions = 45,
        banned = false,
        regDate = "01.01.2024"
    },
    ["TestPlayer"] = {
        balance = 500.00,
        emaBalance = 100.00,
        transactions = 12,
        banned = false,
        regDate = "15.03.2024"
    },
    ["BadPlayer"] = {
        balance = 50.00,
        emaBalance = 0,
        transactions = 3,
        banned = true,
        regDate = "20.05.2024"
    }
}

local testAdmins = {"ZoziDo", "Admin2"}

local testLogs = {
    {time = "12:30:45", text = "🚀 Сервер запущен", level = "SUCCESS"},
    {time = "12:31:00", text = "✅ Игрок ZoziDo вошёл в систему", level = "INFO"},
    {time = "12:31:15", text = "💰 Продажа: Алмаз x5 на 500 Coina", level = "SUCCESS"},
    {time = "12:32:00", text = "📩 Репорт от TestPlayer: Всё работает!", level = "WARN"},
    {time = "12:32:30", text = "❌ Ошибка подключения к терминалу", level = "ERROR"},
    {time = "12:33:00", text = "🛒 Покупка: Зелье x3 за 150 Coina + 50 ЭМЫ", level = "SUCCESS"}
}

local testFeedbacks = {
    {name = "ZoziDo", text = "Отличный сервер!", time = "01.01.2024 12:00"},
    {name = "TestPlayer", text = "Всё работает отлично!", time = "15.03.2024 14:30"}
}

local testReports = {
    {name = "TestPlayer", time = "15.03.2024 14:30", text = "Нашёл баг с продажей"},
    {name = "Player123", time = "20.05.2024 10:00", text = "Игрок BadPlayer читерит"}
}

-- Функция для создания JSON вручную (без библиотеки)
local function toJSON(data)
    if type(data) == "string" then
        return '"' .. data:gsub('"', '\\"') .. '"'
    elseif type(data) == "number" or type(data) == "boolean" then
        return tostring(data)
    elseif type(data) == "table" then
        local parts = {}
        local isArray = true
        local count = 0
        for k, _ in pairs(data) do
            count = count + 1
            if type(k) ~= "number" then isArray = false end
        end
        
        if count == 0 then
            return isArray and "[]" or "{}"
        end
        
        if isArray then
            for i = 1, #data do
                table.insert(parts, toJSON(data[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(data) do
                table.insert(parts, toJSON(k) .. ":" .. toJSON(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

-- Функция для создания HTTP ответа
local function createResponse(data, status)
    status = status or 200
    local statusText = "200 OK"
    if status == 404 then statusText = "404 Not Found" end
    if status == 500 then statusText = "500 Internal Server Error" end
    
    local body = ""
    if type(data) == "table" then
        body = toJSON(data)
    else
        body = tostring(data)
    end
    
    local response = "HTTP/1.1 " .. statusText .. "\r\n"
    response = response .. "Content-Type: application/json\r\n"
    response = response .. "Access-Control-Allow-Origin: *\r\n"
    response = response .. "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
    response = response .. "Access-Control-Allow-Headers: Content-Type\r\n"
    response = response .. "Connection: close\r\n"
    response = response .. "Content-Length: " .. #body .. "\r\n"
    response = response .. "\r\n"
    response = response .. body
    
    return response
end

-- Функция для обработки API запросов
local function handleAPI(path)
    print("API запрос: " .. path)
    
    -- GET /api/stats
    if path == "/api/stats" then
        return createResponse({
            success = true,
            totalPlayers = 3,
            totalTransactions = 60,
            totalReports = 2,
            totalFeedbacks = 2,
            totalSells = 30,
            totalBuys = 25,
            paused = false,
            online = 2
        })
    end
    
    -- GET /api/players
    if path == "/api/players" then
        local players = {}
        for name, data in pairs(testPlayers) do
            table.insert(players, {
                name = name,
                balance = data.balance,
                emaBalance = data.emaBalance,
                transactions = data.transactions,
                banned = data.banned,
                agreed = true
            })
        end
        return createResponse({
            success = true,
            players = players,
            admins = testAdmins,
            total = #players,
            total_transactions = 60,
            total_reports = 2,
            online = 2,
            paused = false
        })
    end
    
    -- GET /api/logs
    if path == "/api/logs" then
        return createResponse({
            success = true,
            logs = testLogs
        })
    end
    
    -- GET /api/admins
    if path == "/api/admins" then
        return createResponse({
            success = true,
            admins = testAdmins
        })
    end
    
    -- GET /api/feedbacks
    if path == "/api/feedbacks" then
        return createResponse({
            success = true,
            feedbacks = testFeedbacks
        })
    end
    
    -- GET /api/reports
    if path == "/api/reports" then
        return createResponse({
            success = true,
            reports = testReports
        })
    end
    
    -- POST /api/pause
    if path == "/api/pause" then
        return createResponse({
            success = true,
            paused = true
        })
    end
    
    -- POST /api/kill
    if path == "/api/kill" then
        return createResponse({
            success = true,
            sent = 1
        })
    end
    
    -- POST /api/additem
    if path == "/api/additem" then
        return createResponse({
            success = true
        })
    end
    
    -- POST /api/balance
    if path == "/api/balance" then
        return createResponse({
            success = true
        })
    end
    
    -- POST /api/ban
    if path == "/api/ban" then
        return createResponse({
            success = true,
            banned = true
        })
    end
    
    -- POST /api/reset
    if path == "/api/reset" then
        return createResponse({
            success = true
        })
    end
    
    -- POST /api/addadmin
    if path == "/api/addadmin" then
        return createResponse({
            success = true
        })
    end
    
    -- POST /api/removeadmin
    if path == "/api/removeadmin" then
        return createResponse({
            success = true
        })
    end
    
    -- POST /api/update
    if path == "/api/update" then
        return createResponse({
            success = true,
            sent = 1
        })
    end
    
    -- 404
    return createResponse({
        error = "Unknown endpoint: " .. path
    }, 404)
end

-- ============================================
-- ЗАПУСК HTTP СЕРВЕРА
-- ============================================

local function startServer()
    print("\n📡 Запуск HTTP сервера...")
    
    -- Пробуем разные порты
    local ports = {8080, 8888, 3000, 5000}
    local socket = nil
    
    for _, port in ipairs(ports) do
        print("  Пробуем порт " .. port .. "...")
        local ok, result = pcall(function()
            return internet.socket()
        end)
        
        if ok and result then
            socket = result
            local bindOk = pcall(function()
                socket:listen(port)
            end)
            
            if bindOk then
                print("✅ Сервер запущен на порту " .. port)
                print("🌐 Откройте в браузере: http://localhost:" .. port)
                print("📋 Доступные API:")
                print("   GET  /api/players - список игроков")
                print("   GET  /api/logs - логи сервера")
                print("   GET  /api/stats - статистика")
                print("   GET  /api/admins - администраторы")
                print("   GET  /api/feedbacks - отзывы")
                print("   GET  /api/reports - репорты")
                print("=" .. string.rep("=", 40))
                break
            else
                print("  ❌ Не удалось занять порт " .. port)
            end
        end
    end
    
    if not socket then
        print("❌ Не удалось создать сервер на всех портах")
        return
    end
    
    -- Основной цикл
    while true do
        local ok, client = pcall(function()
            return socket:accept(5)  -- Таймаут 5 секунд
        end)
        
        if ok and client then
            -- Обрабатываем клиента в pcall чтобы не падало
            pcall(function()
                -- Читаем запрос
                local request = ""
                local readStart = computer.uptime()
                
                while computer.uptime() - readStart < 2 do  -- Таймаут 2 секунды
                    local ok2, chunk = pcall(function()
                        return client:read(256)
                    end)
                    if ok2 and chunk then
                        request = request .. chunk
                        if #request > 2048 then break end  -- Максимум 2KB
                    else
                        break
                    end
                end
                
                -- Парсим HTTP запрос
                local method = "GET"
                local path = "/"
                
                if request and #request > 0 then
                    local firstLine = request:match("([^\r\n]+)")
                    if firstLine then
                        local parts = {}
                        for part in firstLine:gmatch("%S+") do
                            table.insert(parts, part)
                        end
                        if parts[1] then method = parts[1] end
                        if parts[2] then path = parts[2] end
                    end
                    
                    print(string.format("📨 %s %s", method, path))
                    
                    -- Обрабатываем OPTIONS (CORS preflight)
                    if method == "OPTIONS" then
                        local response = "HTTP/1.1 200 OK\r\n"
                        response = response .. "Access-Control-Allow-Origin: *\r\n"
                        response = response .. "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
                        response = response .. "Access-Control-Allow-Headers: Content-Type\r\n"
                        response = response .. "Content-Length: 0\r\n"
                        response = response .. "Connection: close\r\n"
                        response = response .. "\r\n"
                        pcall(function() client:write(response) end)
                    -- Обрабатываем API запросы
                    elseif path:match("^/api/") then
                        local response = handleAPI(path)
                        pcall(function() client:write(response) end)
                    -- Отдаём index.html
                    elseif path == "/" or path == "/index.html" then
                        local html = [[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PIM Market Admin</title>
    <style>
        body { 
            font-family: monospace; 
            background: #0A0A0F; 
            color: #00E5C9; 
            padding: 20px;
            margin: 0;
        }
        .header {
            background: #14141F;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            border: 1px solid #00E5C9;
        }
        .header h1 { color: #8B5CF6; margin: 0; }
        .status { 
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            background: #00FFAA;
            color: #000;
            font-weight: bold;
            margin-top: 10px;
        }
        .log-container {
            background: #14141F;
            border-radius: 10px;
            padding: 15px;
            height: 500px;
            overflow-y: auto;
            border: 1px solid #333;
        }
        .log-entry {
            padding: 5px 0;
            border-bottom: 1px solid #1F1F2E;
            font-size: 13px;
            line-height: 1.5;
        }
        .log-time { color: #555; }
        .log-success { color: #00FFAA; }
        .log-info { color: #00E5C9; }
        .log-warn { color: #FFA500; }
        .log-error { color: #FF4D7A; }
        .log-important { color: #8B5CF6; }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .stat-card {
            background: #14141F;
            padding: 15px;
            border-radius: 8px;
            border-left: 3px solid #8B5CF6;
        }
        .stat-label { color: #555; font-size: 12px; }
        .stat-value { color: #F0F0FF; font-size: 24px; font-weight: bold; }
        .btn {
            background: #8B5CF6;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-family: monospace;
            margin: 5px;
        }
        .btn:hover { opacity: 0.8; }
        .tabs {
            display: flex;
            gap: 10px;
            margin: 20px 0;
        }
        .tab {
            padding: 10px 20px;
            background: #14141F;
            border: 1px solid #333;
            color: #555;
            border-radius: 5px;
            cursor: pointer;
        }
        .tab.active {
            background: #8B5CF6;
            color: white;
            border-color: #8B5CF6;
        }
        .content {
            display: none;
            background: #14141F;
            padding: 20px;
            border-radius: 10px;
            border: 1px solid #333;
        }
        .content.active { display: block; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 PIM Market Admin</h1>
        <div class="status" id="status">🟢 Онлайн</div>
        <p style="color: #555; margin-top: 10px;">
            Тестовый сервер | Данные демонстрационные
        </p>
    </div>
    
    <div class="stats" id="stats"></div>
    
    <div class="tabs">
        <div class="tab active" onclick="switchTab('logs')">📋 Логи</div>
        <div class="tab" onclick="switchTab('players')">👥 Игроки</div>
        <div class="tab" onclick="switchTab('feedbacks')">📝 Отзывы</div>
        <div class="tab" onclick="switchTab('reports')">📩 Репорты</div>
    </div>
    
    <div id="content-logs" class="content active">
        <div class="log-container" id="logs"></div>
    </div>
    
    <div id="content-players" class="content">
        <div id="players"></div>
    </div>
    
    <div id="content-feedbacks" class="content">
        <div id="feedbacks"></div>
    </div>
    
    <div id="content-reports" class="content">
        <div id="reports"></div>
    </div>
    
    <script>
        async function loadData() {
            try {
                // Загружаем логи
                const logsResponse = await fetch('/api/logs');
                const logsData = await logsResponse.json();
                if (logsData.logs) {
                    let html = '';
                    for (const log of logsData.logs) {
                        const colorClass = 'log-' + (log.level || 'info').toLowerCase();
                        html += `<div class="log-entry">
                            <span class="log-time">[${log.time}]</span>
                            <span class="${colorClass}">${log.text}</span>
                        </div>`;
                    }
                    document.getElementById('logs').innerHTML = html;
                }
                
                // Загружаем статистику
                const statsResponse = await fetch('/api/stats');
                const statsData = await statsResponse.json();
                document.getElementById('stats').innerHTML = `
                    <div class="stat-card">
                        <div class="stat-label">👥 Игроков</div>
                        <div class="stat-value">${statsData.totalPlayers || 0}</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-label">💰 Транзакций</div>
                        <div class="stat-value">${statsData.totalTransactions || 0}</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-label">📩 Репортов</div>
                        <div class="stat-value">${statsData.totalReports || 0}</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-label">📝 Отзывов</div>
                        <div class="stat-value">${statsData.totalFeedbacks || 0}</div>
                    </div>
                `;
                
                // Загружаем игроков
                const playersResponse = await fetch('/api/players');
                const playersData = await playersResponse.json();
                if (playersData.players) {
                    let html = '<table style="width:100%;border-collapse:collapse;">';
                    html += '<tr style="color:#555;border-bottom:1px solid #333;">';
                    html += '<th style="text-align:left;padding:10px;">Игрок</th>';
                    html += '<th style="text-align:right;padding:10px;">Coina</th>';
                    html += '<th style="text-align:right;padding:10px;">ЭМЫ</th>';
                    html += '<th style="text-align:right;padding:10px;">Транз.</th>';
                    html += '<th style="text-align:center;padding:10px;">Статус</th>';
                    html += '</tr>';
                    for (const player of playersData.players) {
                        const isAdmin = playersData.admins && playersData.admins.includes(player.name);
                        const statusColor = player.banned ? '#FF4D7A' : '#00FFAA';
                        const statusText = player.banned ? 'Забанен' : (isAdmin ? 'Админ' : 'Активен');
                        html += `<tr style="border-bottom:1px solid #1F1F2E;">
                            <td style="padding:10px;">${player.name}</td>
                            <td style="padding:10px;text-align:right;">${player.balance.toFixed(2)} ₵</td>
                            <td style="padding:10px;text-align:right;">${player.emaBalance.toFixed(2)} ۞</td>
                            <td style="padding:10px;text-align:right;">${player.transactions}</td>
                            <td style="padding:10px;text-align:center;color:${statusColor};">${statusText}</td>
                        </tr>`;
                    }
                    html += '</table>';
                    document.getElementById('players').innerHTML = html;
                }
                
                // Загружаем отзывы
                const feedbacksResponse = await fetch('/api/feedbacks');
                const feedbacksData = await feedbacksResponse.json();
                if (feedbacksData.feedbacks) {
                    let html = '';
                    for (const fb of feedbacksData.feedbacks) {
                        html += `<div style="padding:10px;border-bottom:1px solid #1F1F2E;">
                            <div style="color:#8B5CF6;font-weight:bold;">👤 ${fb.name}</div>
                            <div style="color:#555;font-size:12px;">[${fb.time}]</div>
                            <div style="margin-top:5px;">${fb.text}</div>
                        </div>`;
                    }
                    document.getElementById('feedbacks').innerHTML = html || '<div style="color:#555;">Нет отзывов</div>';
                }
                
                // Загружаем репорты
                const reportsResponse = await fetch('/api/reports');
                const reportsData = await reportsResponse.json();
                if (reportsData.reports) {
                    let html = '';
                    for (const report of reportsData.reports) {
                        html += `<div style="padding:10px;border-bottom:1px solid #1F1F2E;">
                            <div style="color:#FFA500;font-weight:bold;">📩 ${report.name}</div>
                            <div style="color:#555;font-size:12px;">[${report.time}]</div>
                            <div style="margin-top:5px;">${report.text}</div>
                        </div>`;
                    }
                    document.getElementById('reports').innerHTML = html || '<div style="color:#555;">Нет репортов</div>';
                }
                
                // Обновляем статус
                const status = document.getElementById('status');
                if (statsData.paused) {
                    status.textContent = '⏸️ Пауза';
                    status.style.background = '#FFA500';
                } else {
                    status.textContent = '🟢 Онлайн';
                    status.style.background = '#00FFAA';
                }
                
            } catch (e) {
                console.error('Ошибка:', e);
            }
        }
        
        function switchTab(tab) {
            document.querySelectorAll('.content').forEach(c => c.classList.remove('active'));
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.getElementById('content-' + tab).classList.add('active');
            event.target.classList.add('active');
        }
        
        // Загружаем данные и обновляем каждые 5 секунд
        loadData();
        setInterval(loadData, 5000);
    </script>
</body>
</html>]]
                        
                        local response = "HTTP/1.1 200 OK\r\n"
                        response = response .. "Content-Type: text/html; charset=utf-8\r\n"
                        response = response .. "Access-Control-Allow-Origin: *\r\n"
                        response = response .. "Content-Length: " .. #html .. "\r\n"
                        response = response .. "Connection: close\r\n"
                        response = response .. "\r\n"
                        response = response .. html
                        pcall(function() client:write(response) end)
                    else
                        local response = createResponse({error = "Not found: " .. path}, 404)
                        pcall(function() client:write(response) end)
                    end
                end
                
                pcall(function() client:close() end)
            end)
        end
        
        -- Проверяем события (чтобы не зависало)
        event.pull(0.1)
    end
end

-- Запускаем сервер
local ok, err = pcall(startServer)
if not ok then
    print("❌ Ошибка запуска сервера:")
    print("   " .. tostring(err))
    print("\n💡 Возможные причины:")
    print("  1. Нет интернет-карты в компьютере")
    print("  2. Все порты заняты")
    print("  3. Недостаточно памяти")
end
