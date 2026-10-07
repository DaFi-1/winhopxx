-- lua/winhop.lua
local window_hop = {}

local api = vim.api

local labels = {
  "a","b","c","d","e","f","g","h","i","j","k","l",
  "m","n","o","p","q","r","s","t","u","v","w","x",
  "y","z"
}

-- Índice reverso letra -> posição: busca O(1) da tecla digitada
local label_index = {}
for i, label in ipairs(labels) do
  label_index[label] = i
end

local ESC = "\27"
local BORDER = 2 -- a borda soma 1 célula de cada lado (largura e altura)
local WINHL = "Normal:WinHopLabel,FloatBorder:WinHopBorder"

-- Grupo de destaque próprio (o usuário pode sobrescrever)
-- Paleta: letra e borda brancas, sem cor de fundo (transparente)
local function set_highlights()
  api.nvim_set_hl(0, "WinHopLabel", { fg = "#FFFFFF", bold = true, default = true })
  api.nvim_set_hl(0, "WinHopBorder", { fg = "#FFFFFF", default = true })
end
set_highlights()

-- :colorscheme limpa os grupos, então reaplica depois de trocar o tema
api.nvim_create_autocmd("ColorScheme", {
  group = api.nvim_create_augroup("WinHopHighlights", { clear = true }),
  callback = set_highlights,
})

-- Cache das etiquetas: cada letra é montada (concatenação + strwidth) e
-- escrita num buffer uma única vez; as ativações seguintes só reabrem a janela.
local cache = { big = {}, small = {} }

local function memo(store, key, build)
  local entry = store[key]
  if not entry then
    entry = build(key)
    store[key] = entry
  end
  return entry
end

-- Letras grandes em ASCII art (fonte FIGlet "banner3"), carregada só no 1º uso
local function build_big(label)
  local lines = { "" }
  for i, row in ipairs(require("winhop.font")[label]) do
    lines[i + 1] = "  " .. row .. "  "
  end
  lines[#lines + 1] = ""
  -- strwidth: "█" tem 3 bytes, mas ocupa 1 coluna
  return { lines = lines, width = api.nvim_strwidth(lines[2]), height = #lines }
end

local function build_small(label)
  local text = "  " .. label:upper() .. "  "
  return { lines = { "", text, "" }, width = #text, height = 3 }
end

-- Monta as linhas da letra: grande se couber na janela, pequena caso contrário
local function pick_label(label, win_w, win_h)
  local big = memo(cache.big, label, build_big)
  if big.height + BORDER <= win_h and big.width + BORDER <= win_w then
    return big
  end
  return memo(cache.small, label, build_small)
end

-- Buffer reaproveitado entre ativações; recriado se alguém o apagou
local function label_buf(entry)
  if not (entry.buf and api.nvim_buf_is_valid(entry.buf)) then
    entry.buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(entry.buf, 0, -1, false, entry.lines)
    vim.bo[entry.buf].modifiable = false
  end
  return entry.buf
end

-- Janelas flutuantes reaproveitadas, uma por letra em cada aba.
-- Abrir+desenhar+fechar floats deixa cada ciclo seguinte mais lento dentro do
-- próprio Neovim (medido: ~0.3µs a mais por float já criado); esconder/mostrar
-- com `hide` tem custo constante. Floats escondidos e não focáveis são ignorados
-- por <C-w>w e :windo, e fechados normalmente por :only/:q.
local pools = {} -- [tabpage] = { [slot] = float }

local function tab_pool()
  local tab = api.nvim_get_current_tabpage()
  local pool = pools[tab]
  if not pool then
    -- Descarta pools de abas já fechadas (os floats morreram junto com elas)
    for t in pairs(pools) do
      if not api.nvim_tabpage_is_valid(t) then pools[t] = nil end
    end
    pool = {}
    pools[tab] = pool
  end
  return pool
end

-- Mostra a letra centralizada na janela alvo, usando o float do slot
local function show_label(pool, slot, winid)
  local win_w = api.nvim_win_get_width(winid)
  local win_h = api.nvim_win_get_height(winid)
  local entry = pick_label(labels[slot], win_w, win_h)
  local buf = label_buf(entry)

  local cfg = {
    relative = "win",
    win = winid,
    row = math.max(0, math.floor((win_h - entry.height - BORDER) / 2)),
    col = math.max(0, math.floor((win_w - entry.width - BORDER) / 2)),
    width = entry.width,
    height = entry.height,
    hide = false,
  }

  local float = pool[slot]
  if float and api.nvim_win_is_valid(float) then
    if api.nvim_win_get_buf(float) == buf then
      api.nvim_win_set_config(float, cfg) -- caminho comum: só reposiciona
      return float
    end
    -- Trocou entre letra grande/pequena (raro): recria sem disparar autocmds
    api.nvim_win_close(float, true)
  end

  cfg.style = "minimal"
  cfg.border = "rounded"
  cfg.focusable = false
  cfg.noautocmd = true
  cfg.zindex = 250
  float = api.nvim_open_win(buf, false, cfg)
  vim.wo[float].winhl = WINHL
  pool[slot] = float
  return float
end

-- Janelas normais da aba atual, no máximo uma por letra disponível
local function target_windows()
  local wins = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    -- Ignora janelas flutuantes (popups, notificações etc.)
    if api.nvim_win_get_config(win).relative == "" then
      wins[#wins + 1] = win
      if #wins == #labels then break end
    end
  end
  return wins
end

-- Mostra as letras e espera a tecla; os floats são ocultados ao terminar
local function prompt(wins)
  local pool = tab_pool()
  local ok, key = pcall(function()
    for i, win in ipairs(wins) do
      show_label(pool, i, win)
    end
    -- Garante que as letras aparecem antes de esperar a tecla
    vim.cmd.redraw()
    -- <C-c> lança erro aqui; o pcall externo trata como cancelamento
    return vim.fn.getcharstr()
  end)

  -- Oculta os floats em vez de destruí-los, garantindo performance constante
  for i = 1, #wins do
    local float = pool[i]
    if float and api.nvim_win_is_valid(float) then
      pcall(api.nvim_win_set_config, float, { hide = true })
    end
  end

  if ok then return key end
end

function window_hop.activate()
  local wins = target_windows()
  if #wins < 2 then return end -- só uma janela: não há para onde pular

  local key = prompt(wins)
  if not key or key == ESC then return end -- <C-c> ou <Esc> cancelam

  local win = wins[label_index[key:lower()]]
  if not (win and api.nvim_win_is_valid(win)) then
    vim.notify("Letra inválida ❗", vim.log.levels.WARN)
    return
  end
  -- pcall: falha em lugares como a janela de comandos (q:) com E11
  local jumped, err = pcall(api.nvim_set_current_win, win)
  if not jumped then
    vim.notify(err, vim.log.levels.WARN)
  end
end

-- setup permite ativar via keymap apenas quando o usuário quiser
function window_hop.setup()
  vim.keymap.set("n", "<Space>w", window_hop.activate, {
    silent = true,
    desc = "WinHop: pular para janela",
  })
end

return window_hop
