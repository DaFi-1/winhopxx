-- lua/winhop.lua
local window_hop = {}

local labels = {
  "a","b","c","d","e","f","g","h","i","j","k","l",
  "m","n","o","p","q","r","s","t","u","v","w","x",
  "y","z"
}

local state = {
  active = false,
  win_map = {},
}

local ns = vim.api.nvim_create_namespace("WindowHopOverlay")

-- Cria overlay fixado no topo da janela
local function mark_window(winid, label)
  local buf = vim.api.nvim_win_get_buf(winid)
  local bufname = vim.api.nvim_buf_get_name(buf)
  bufname = bufname ~= "" and vim.fn.fnamemodify(bufname, ":t") or "[No Name]"
  local text = label:upper() .. " - " .. bufname
  -- Pega a primeira linha VISÍVEL da janela
  local topline = vim.fn.line("w0", winid) - 1
  -- Extmark fixado na janela, não no buffer
  vim.api.nvim_buf_set_extmark(buf, ns, topline, 0, {
    virt_text = {{ text, "IncSearch" }},
    virt_text_pos = "overlay",
    virt_text_win_col = 0,
    hl_mode = "combine",
    priority = 200,
  })
end

-- Remove overlays
local function clear_marks()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  end
end

function window_hop.activate()
  if state.active then return end
  state.active = true
  state.win_map = {}
  local wins = vim.api.nvim_tabpage_list_wins(0)
  local idx = 1
  for _, win in ipairs(wins) do
    if idx <= #labels then
      local label = labels[idx]
      state.win_map[label] = win
      mark_window(win, label)
      idx = idx + 1
    end
  end

  vim.schedule(function()
    local char = vim.fn.getcharstr()
    window_hop.jump(char)
  end)
end

function window_hop.jump(char)
  clear_marks()
  state.active = false
  local win = state.win_map[char]
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  else
    vim.notify("Letra inválida ❗", vim.log.levels.WARN)
  end
end

-- setup permite ativar via keymap apenas quando o usuário quiser
function window_hop.setup()
  vim.keymap.set("n", "<Space>w", function()
    window_hop.activate()
  end, { noremap = true, silent = true })
end

return window_hop
