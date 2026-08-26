---@class minibuffer.builtin.Manpage
---@field name string
---@field section string
---@field description string
---@field search string

local function parse_manpages(lines)
  local items = {}

  for _, line in ipairs(lines) do
    local name, section, description = line:match("^(.+)%s+%(([^)]+)%)%s+%-%s+(.*)$")
    if name and section then
      -- `man -k` can return aliases:
      -- printf, fprintf, sprintf (3) - ...
      local first_name = name:match("^([^,%s]+)")
      if first_name then
        items[#items + 1] = {
          name = first_name,
          section = section,
          description = description,
          search = table.concat({
            first_name,
            section,
            description,
          }, " "),
        }
      end
    end
  end
  table.sort(items, function(a, b)
    if a.name == b.name then
      return a.section < b.section
    end

    return a.name < b.name
  end)

  return items
end

local function format_fn(item)
  return {
    {
      text = item.name,
      hl = "Identifier",
    },
    {
      text = "  (" .. item.section .. ")",
      hl = "Number",
    },
    {
      text = "  " .. item.description,
      hl = "Comment",
    },
  }
end

local function filter_fn(ctx)
  if ctx.input == "" then
    return ctx.items
  end
  local input = ctx.input:lower()

  local exact = {}
  local prefix = {}
  local fuzzy = {}
  local fuzzy_items = {}
  local fuzzy_lookup = {}
  for _, item in ipairs(ctx.items) do
    local name = item.name:lower()
    if name == input then
      exact[#exact + 1] = item
    elseif vim.startswith(name, input) then
      prefix[#prefix + 1] = item
    else
      fuzzy_items[#fuzzy_items + 1] = item.search
      fuzzy_lookup[item.search] = item
    end
  end

  -- Keep prefix matches alphabetically ordered.
  table.sort(prefix, function(a, b)
    return a.name < b.name
  end)

  -- Fuzzy matches are ranked by matchfuzzy().
  local matches = vim.fn.matchfuzzy(fuzzy_items, input)
  for _, key in ipairs(matches) do
    fuzzy[#fuzzy + 1] = fuzzy_lookup[key]
  end

  local results = {}
  for _, item in ipairs(exact) do
    results[#results + 1] = item
  end
  for _, item in ipairs(prefix) do
    results[#results + 1] = item
  end
  for _, item in ipairs(fuzzy) do
    results[#results + 1] = item
  end

  return results
end

return function()
  require("minibuffer.internal.guard").check()

  require("minibuffer").select({
    resumable = true,
    prompt = "Manpages: ",
    multi = false,
    dynamic_height = false,
    max_height = 15,
    format_fn = format_fn,
    filter_fn = filter_fn,
    fetch_fn = function(input, cb)
      vim.system({ "man", "-k", input ~= "" and input or "." }, {
        text = true,
      }, function(res)
        if res.code ~= 0 then
          vim.schedule(function()
            cb(nil, res.stderr)
          end)
          return
        end

        local items = parse_manpages(vim.split(res.stdout or "", "\n", {
          trimempty = true,
        }))
        vim.schedule(function()
          cb(items)
        end)
      end)
    end,
    on_accept = function(selection)
      local item = selection[1].item
      if not item then
        return
      end
      vim.cmd("Man " .. item.section .. " " .. item.name)
    end,
  })
end
