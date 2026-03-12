local M = {}

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  vim.notify("telescope.nvim not found", vim.log.levels.ERROR)
  return M
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

---------------------------------------------------------------------
-- Icons (Nerd Font recommended)
---------------------------------------------------------------------
local ICONS = {
  function_ = "󰊕",
  method    = "󰆧",
  struct    = "󰙅",
  class     = "󰌗",
  enum      = "󰕘",
  macro     = "󰏿",
  heading   = "󰉫",
  variable  = "󰀫",
  module    = "󰏗",
  label     = "󰌋",
  default   = "󰈙",
}

---------------------------------------------------------------------
-- Filetype → Treesitter language map
---------------------------------------------------------------------
local LANG_MAP = {
  c = "c",
  cpp = "cpp",
  java = "java",
  python = "python",
  lua = "lua",
  bash = "bash",
  sh = "bash",
  xml = "xml",
  asm = "asm",
  s = "asm",
  S = "asm",
  cs = "c_sharp",
  make = "make",
  diff = "diff",
  vue = "vue",
  php = "php",
  markdown = "markdown",
  rst = "rst",
  qmljs = "qmljs",
  rust = "rust",
  kconfig = "kconfig",
  dts = "devicetree",
  udevrules = "udev",
  bp = "bp",
  bitbake = "bitbake",
  toml = "toml",
}

---------------------------------------------------------------------
-- Treesitter queries (semantic captures)
---------------------------------------------------------------------
local QUERIES = {
  c = [[
    (function_definition
      declarator: [
        (function_declarator declarator: (identifier) @function_)
        (pointer_declarator declarator:
          (function_declarator declarator: (identifier) @function_))
      ])
    (struct_specifier name: (type_identifier) @struct body:(_))
    (enum_specifier name: (type_identifier) @enum body:(_))
    (preproc_function_def name: (identifier) @macro)
  ]],

  cpp = [[
    (function_definition declarator: (function_declarator declarator: (_) @function_))
    (class_specifier name: (type_identifier) @class)
    (struct_specifier name: (type_identifier) @struct body:(_))
    (enum_specifier name: (type_identifier) @enum body:(_))
    (preproc_function_def name: (identifier) @macro)
  ]],

  asm= [[
    (label (ident) @label)
  ]],

  rust = [[
    (source_file (function_item name: (identifier) @function_))
    (struct_item name: (_) @struct body: (_))
    (enum_item name: (_) @enum)
    (trait_item (visibility_modifier) name: (_) @impl_trait body: (_))
    (impl_item trait: (_) @impl_trait @impl_trait type: (_) @impl_for body: (declaration_list (function_item name: (identifier) @method)))
    (impl_item trait: (_)? type: (_) @impl_for body: (declaration_list (function_item name: (identifier) @method)))
  ]],

  lua = [[
    (function_declaration name: (_) @function_)
    (assignment_statement
      (variable_list (identifier) @function_)
      (expression_list (function_definition)))
  ]],

  python = [[
    (function_definition name: (identifier) @function_)
    (class_definition name: (identifier) @class)
  ]],

  java = [[
    (method_declaration name: (identifier) @method)
    (class_declaration name: (identifier) @class)
    (constructor_declaration name: (identifier) @method)
  ]],

  bash = [[
    (function_definition name: (word) @function_)
  ]],

  c_sharp = [[
    (method_declaration name: (identifier) @method)
    (constructor_declaration name: (identifier) @method)
    (class_declaration name: (identifier) @class)
    (struct_declaration name: (identifier) @struct)
    (enum_declaration name: (identifier) @enum)
  ]],

  markdown = [[
    (section (atx_heading) @heading)
  ]],

  rst = [[
    (section (title) @heading)
  ]],

  qmljs = [[
    (ui_object_definition type_name: (identifier) @class)
  ]],

  diff= [[
    (block (command (filename) @label))
  ]],

  kconfig= [[
    (config name: (_) @label)
    (menu name: (_) @struct)
  ]],

  devicetree= [[
    (node name: (reference) @label)
    (node name: (identifier) @label)
    (node name: (identifier) @impl_trait address: (unit_address) @method)
  ]],

  udev= [[
    (rule (match) @label)
  ]],

  bp= [[
    (module type: (_) @function)
  ]],

  make= [[
    (rule (targets (word) @label))
  ]],

  bitbake= [[
    (function_definition (identifier) @function)
    (inherit_directive (inherit_path)) @label
    (python_function_definition name: (_) @function)
    (anonymous_python_function (identifier) @function)

  ]],

  toml= [[
    (table (dotted_key) @label)
    (table (bare_key) @label)
    (table_array_element (bare_key) @label)
    (table_array_element (dotted_key) @label)
  ]],
}

---------------------------------------------------------------------
-- Main function
---------------------------------------------------------------------
function M.show_functions_telescope()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  local lang = LANG_MAP[ft]

  if not lang then
    vim.notify("Unsupported filetype: " .. ft, vim.log.levels.WARN)
    return
  end

  local query_str = QUERIES[lang]
  if not query_str then
    vim.notify("No Treesitter query for: " .. lang, vim.log.levels.WARN)
    return
  end

  local parser = vim.treesitter.get_parser(bufnr, lang)
  if not parser then
    vim.notify("No Treesitter parser for: " .. lang, vim.log.levels.WARN)
    return
  end

  local tree = parser:parse()[1]
  local root = tree:root()
  local query = vim.treesitter.query.parse(lang, query_str)

  local items = {}
  local previewers = require("telescope.previewers")

  for _, match in query:iter_matches(root, bufnr) do
    local trait, target, method
    local fallback_node, fallback_capture
  
    --  Collect
    for id, nodes in pairs(match) do
      local capture = query.captures[id]
      local node = nodes[1]
  
      if capture == "impl_trait" then
        trait = vim.treesitter.get_node_text(node, bufnr)
      elseif capture == "impl_for" then
        target = vim.treesitter.get_node_text(node, bufnr)
      elseif capture == "method" then
        method = node
      else
        -- store normal symbols for fallback
        fallback_node = node
        fallback_capture = capture
      end
    end
    -- Decide & insert ONCE
  
    -- impl method
    if method then
      local row = select(1, method:range())
      local name = vim.treesitter.get_node_text(method, bufnr)
      if trait then
        table.insert(items, {
          text = string.format("󰆧 %s::%s → %s", trait, name, target),
          kind = "method",
          filename = vim.api.nvim_buf_get_name(bufnr),
          lnum = row + 1,
        })
      elseif target then
        table.insert(items, {
          text = string.format("󰆧 %s → %s",name, target),
          kind = "method",
          filename = vim.api.nvim_buf_get_name(bufnr),
          lnum = row + 1,
        })
       else
         table.insert(items, {
           text = string.format("󰆧 %s",name),
           kind = "method",
           filename = vim.api.nvim_buf_get_name(bufnr),
           lnum = row + 1,
         })
      end
    -- normal symbol
    elseif fallback_node and fallback_capture then
      local row = select(1, fallback_node:range())
      local text = vim.treesitter.get_node_text(fallback_node, bufnr)
      local icon = ICONS[fallback_capture] or ICONS.default
  
      table.insert(items, {
        text = string.format("%s  %s", icon, text),
        kind = fallback_capture,
        filename = vim.api.nvim_buf_get_name(bufnr),
        lnum = row + 1,
      })
    end
  end

  if vim.tbl_isempty(items) then
    vim.notify("No symbols found", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = lang:upper() .. " Outline",
    layout_strategy = "horizontal",
    layout_config = {
      width = 0.9,
      height = 0.95,
      preview_width = 0.55,
    },
    finder = finders.new_table {
      results = items,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.text,
          ordinal = entry.kind .. " " .. entry.text,
          filename = entry.filename,
          lnum = entry.lnum,
          col = 1,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      define_preview = function(self, entry)
        local preview_bufnr = self.state.bufnr
        local filename = entry.filename or entry.path
        if not filename then return end
    
        -- Create a temporary buffer for the source file
        local source_bufnr = vim.fn.bufadd(filename)
        vim.fn.bufload(source_bufnr)
    
        -- Get lines from the loaded buffer
        local lines = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
    
        -- Put them into preview buffer
        vim.api.nvim_buf_set_lines(preview_bufnr, 0, -1, false, lines)
    
        vim.bo[preview_bufnr].bufhidden = "wipe"
        vim.bo[preview_bufnr].swapfile = false
    
        local ft = vim.filetype.match({ filename = filename })
        if ft then
          vim.bo[preview_bufnr].filetype = ft
        end
    
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(self.state.winid) then
            local line_count = vim.api.nvim_buf_line_count(preview_bufnr)
            local target_line = math.max(1, math.min(entry.lnum or 1, line_count))
    
            pcall(vim.api.nvim_win_set_cursor, self.state.winid, { target_line, 0 })
            vim.api.nvim_win_set_option(self.state.winid, "cursorline", true)
    
            vim.api.nvim_buf_add_highlight(
              preview_bufnr,
              -1,
              "TelescopePreviewLine",
              target_line - 1,
              0,
              -1
            )
    
            vim.api.nvim_win_call(self.state.winid, function()
              vim.cmd("normal! zz")
            end)
          end
        end)
        -- Fix: Use pcall and ensure lnum is within valid bounds
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(self.state.winid) then
            local line_count = vim.api.nvim_buf_line_count(bufnr)
            local target_line = math.max(1, math.min(entry.lnum, line_count))
            
            pcall(vim.api.nvim_win_set_cursor, self.state.winid, { target_line, 0 })
            
            -- Center the view
            vim.api.nvim_win_call(self.state.winid, function()
              vim.cmd("normal! zz")
            end)
          end
        end)
    
        vim.schedule(function()
          -- pcall(vim.treesitter.start, bufnr)
          pcall(vim.treesitter.start, bufnr, lang)
        end)
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
      end)
      return true
    end,
  }):find()
end

---------------------------------------------------------------------
-- User command
---------------------------------------------------------------------
vim.api.nvim_create_user_command(
  "ShowFunctionsTelescope",
  M.show_functions_telescope,
  { desc = "Treesitter outline (functions / structs / classes / headings)" }
)

return M
