---@diagnostic disable: undefined-global

local function utf8_sub(str, start_char, end_char)
  local start_byte = utf8.offset(str, start_char)
  local end_byte = end_char and (utf8.offset(str, end_char + 1) - 1) or #str

  if not start_byte or not end_byte then
    return ""
  end

  return string.sub(str, start_byte, end_byte)
end

-- Cursor index and file count of the tab this status line belongs to.
local function tab_pos(self)
  local cur = self._tab.current
  return cur.cursor, #cur.files
end

local function setup(_, options)
  options = options or {}

  local default_separators = {
    angly = { "", "", "", "" },
    curvy = { "", "", "", "" },
    liney = { "", "", "|", "|" },
    empty = { "", "", "", "" },
  }
  local separators =
    default_separators[options.separator_style or "angly"] or default_separators.angly

  local separator_color = options.secondary_color
    or th.which.separator_style:fg()
    or "darkgray"

  local config = {
    separator_open = options.separator_open or separators[1],
    separator_close = options.separator_close or separators[2],
    separator_open_thin = options.separator_open_thin or separators[3],
    separator_close_thin = options.separator_close_thin or separators[4],
    separator_head = options.separator_head or "",
    separator_tail = options.separator_tail or "",

    select_symbol = options.select_symbol or "S",
    yank_symbol = options.yank_symbol or "Y",

    filename_max_length = options.filename_max_length or 24,
    filename_truncate_length = options.filename_truncate_length or 6,
    filename_truncate_separator = options.filename_truncate_separator or "...",

    permissions_style = options.permissions_style or "octal",
    separator_color = separator_color,
    color = options.color,
    default_files_color = options.default_files_color or separator_color,
    selected_files_color = options.selected_files_color
      or th.mgr.count_selected:bg()
      or "white",
    yanked_files_color = options.yanked_files_color
      or th.mgr.count_copied:bg()
      or "green",
    cut_files_color = options.cut_files_color or th.mgr.count_cut:bg() or "red",
    mask_color = th.which.mask:bg() or "black",
  }

  -- Suppresses yazi's default file counter; yazbar renders its own.
  function Header:count()
    return ui.Line({})
  end

  function Status:mode()
    local mode = tostring(self._tab.mode):upper()
    local style = self:style()

    return ui.Line({
      ui.Span(config.separator_head):fg(config.color or style.main:bg()),
      ui.Span(" " .. mode .. " ")
        :fg(config.mask_color)
        :bg(config.color or style.main:bg()),
    })
  end

  function Status:length()
    local h = self._current.hovered
    local style = self:style()
    local len = h and h.stat.len or 0

    return ui.Span(
      config.separator_close .. " " .. ya.readable_size(len) .. " "
    )
      :fg(config.color or style.main:bg())
      :bg(config.separator_color)
  end

  -- yazi exposes permissions as an rwx string, so octal means reading it back.
  -- Only defined when asked for: otherwise yazi renders its own, colours and all.
  if config.permissions_style == "octal" then
    function Status:perm()
      local perm = self._current.hovered and self._current.hovered.stat:perm()
      if not perm then
        return ""
      end

      local special = (perm:sub(4, 4):find("[sS]") and 4 or 0)
        + (perm:sub(7, 7):find("[sS]") and 2 or 0)
        + (perm:sub(10, 10):find("[tT]") and 1 or 0)

      local oct = 0
      for i = 1, 3 do
        local group = perm:sub(i * 3 - 1, i * 3 + 1)
        local exec = group:sub(3, 3)
        oct = oct * 8 + (group:sub(1, 1) == "r" and 4 or 0)
          + (group:sub(2, 2) == "w" and 2 or 0)
          + (exec ~= "-" and exec ~= "T" and 1 or 0)
      end

      -- Fixed width: a dash stands in for the missing setuid/setgid/sticky digit.
      local digits = string.format("%03o", oct)

      local columns = { th.status.perm_read, th.status.perm_write, th.status.perm_exec }
      local spans = {
        ui.Span(special == 0 and " - " or " " .. string.format("%o", special) .. " ")
          :style(special == 0 and th.status.perm_sep or th.status.perm_type),
      }
      for i = 1, 3 do
        spans[#spans + 1] = ui.Span(digits:sub(i, i)):style(columns[i])
      end

      return ui.Line(spans)
    end
  end

  function Status:name()
    local h = self._current.hovered
    local style = self:style()
    if not h then
      return ui.Line({
        ui.Span(config.separator_close .. " "):fg(config.separator_color),
        ui.Span("Empty dir"):fg(config.color or style.main:bg()),
      })
    end

    local name = h.name
    if utf8.len(name) > config.filename_max_length then
      local base, ext = name:match("^(.+)(%.[^%.]+)$")
      local keep = config.filename_truncate_length
      name = utf8_sub(base or name, 1, keep)
        .. config.filename_truncate_separator
        .. utf8_sub(base or name, -keep)
        .. (ext or "")
    end

    local spans = { ui.Span(config.separator_close .. " "):fg(config.separator_color) }
    local icon = th.icon:match(h, { hovered = true })
    if icon then
      spans[#spans + 1] = ui.Span(icon.text .. " "):style(icon.style)
    end
    spans[#spans + 1] = ui.Span(name):fg(config.color or style.main:bg())
    return ui.Line(spans)
  end

  function Status:files()
    local yanked, selected = #cx.yanked, #cx.active.selected
    local selected_fg = selected > 0 and config.selected_files_color
      or config.default_files_color
    local yanked_fg = yanked > 0
        and (cx.yanked.is_cut and config.cut_files_color or config.yanked_files_color)
      or config.default_files_color

    return ui.Line({
      ui.Span(" " .. config.separator_close_thin .. " ")
        :fg(config.separator_color),
      ui.Span(config.select_symbol .. " " .. selected .. " ")
        :fg(selected_fg),
      ui.Span(config.yank_symbol .. " " .. yanked .. "  "):fg(yanked_fg),
    })
  end

  function Status:modified()
    local hovered = cx.active.current.hovered
    if not (hovered and hovered.stat.mtime) then
      return ""
    end

    return ui.Span(
      hovered.stat.mtime:format({
        year = "system",
        month = "system",
        day = "system",
        hour24 = "system",
        minute = "system",
      }) .. " " .. config.separator_open_thin .. " "
    ):fg(config.separator_color)
  end

  function Status:percent()
    local cursor, length = tab_pos(self)
    local percent = length > 0 and math.floor((cursor + 1) * 100 / length) or 0
    local text = percent == 0 and " Top "
      or percent == 100 and " Bot "
      or string.format(" %2d%% ", percent)

    local style = self:style()
    return ui.Line({
      ui.Span(" " .. config.separator_open):fg(config.separator_color),
      ui.Span(text)
        :fg(config.color or style.main:bg())
        :bg(config.separator_color),
      ui.Span(config.separator_open)
        :fg(config.color or style.main:bg())
        :bg(config.separator_color),
    })
  end

  function Status:position()
    local cursor, length = tab_pos(self)
    local style = self:style()

    return ui.Line({
      ui.Span(
        string.format(" %2d/%-2d ", math.min(cursor + 1, length), length)
      )
        :fg(config.mask_color)
        :bg(config.color or style.main:bg()),
      ui.Span(config.separator_tail):fg(config.color or style.main:bg()),
    })
  end

  Status:children_add(Status.files, 4000, Status.LEFT)
  Status:children_add(Status.modified, 0, Status.RIGHT)
end

return { setup = setup }