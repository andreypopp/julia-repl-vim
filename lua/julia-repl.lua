function logerror(msg)
  vim.api.nvim_echo({{"julia-repl: "..msg, "ErrorMsg"}}, true, {})
end

function loginfo(msg)
  vim.api.nvim_echo({{"julia-repl: "..msg, "InfoMsg"}}, true, {})
end

function connect(opts)
  if opts == nil then opts = {} end
  local host = opts.host or "localhost"
  local port = opts.port or 2345
  local buf = {}
  local id = 0
  local callbacks = {}

  local on_response = function(response)
    data = vim.fn.json_decode(response)
    local callback = callbacks[data.id]
    if callback ~= nil then
      callbacks[data.id] = nil
      callback(data)
    else
      logerror("orphan response: "..response)
    end
  end

  local repl
  local connstr = host..":"..port
  ok, ch = pcall(vim.fn.sockconnect, "tcp", connstr, {
    on_data = function(ch, data, name)
      if #data == 1 and data[1] == '' then -- EOF
        logerror("REPL connection closed")
        if #buf > 0 then
          on_response(table.concat(buf, ''))
          buf = {}
        end
        if opts.on_close then
          opts.on_close()
        end
      else
        for _, chunk in ipairs(data) do
          if chunk == '' and #buf > 0 then
            on_response(table.concat(buf, ''))
            buf = {}
          else
            table.insert(buf, chunk)
          end
        end
      end
    end
  })

  if not ok then
    return logerror("unable to connect to Julia REPL at "..connstr)
  end
  loginfo("connected to Julia REPL at "..connstr)

  function complete(prefix, callback)
    id = id + 1
    data = {type="complete",id=id,full=prefix,partial=prefix}
    callbacks[id] = callback
    vim.fn.chansend(ch, vim.fn.json_encode(data))
    vim.fn.chansend(ch, "\n")
  end

  function eval(code, callback)
    id = id + 1
    data = {type="eval",id=id,code=code}
    callbacks[id] = callback
    vim.fn.chansend(ch, vim.fn.json_encode(data))
    vim.fn.chansend(ch, "\n")
  end

  function input(code, callback)
    id = id + 1
    data = {type="input",id=id,code=code}
    callbacks[id] = callback
    vim.fn.chansend(ch, vim.fn.json_encode(data))
    vim.fn.chansend(ch, "\n")
  end

  function help(symbol, callback)
    symbol = vim.fn.json_encode(symbol)
    eval("eval(REPL.helpmode("..symbol.."))", callback)
  end

  function close()
    vim.fn.chanclose(ch)
  end

  repl = {
    eval=eval,
    input=input,
    complete=complete,
    help=help,
    close=close,
  }
  return repl
end

function setup()
  local buf = vim.fn.bufnr()
  local ok, repl = pcall(vim.api.nvim_buf_get_var, buf, 'julia_repl')
  if ok and repl ~= nil then
    repl.close()
  end
  repl = connect {
    host="localhost",
    port=2345,
    on_close=function()
      vim.api.nvim_buf_set_var(buf, 'julia_repl', nil)
    end
  }
  vim.api.nvim_buf_set_var(buf, 'julia_repl', repl)
  vim.api.nvim_buf_set_option(0, 'omnifunc', 'v:lua.julia_repl_comp')
end

function _G.julia_repl_send(code)
  local repl = vim.b.julia_repl
  if repl == nil or repl == vim.NIL then
    return logerror("not connected to Julia REPL (use :JuliaREPLConnect)")
  end
  repl.input(code, function() end)
end

function _G.julia_repl_comp(findstart, base)
  local repl = vim.b.julia_repl
  if repl == nil then return -2 end
  if findstart == 1 then
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local line_to_cursor = line:sub(1, pos[2])
    local prefixpos = vim.fn.match(line_to_cursor, '\\k\\(\\k\\|\\.\\)*$')
    if prefixpos < 1 then prefixpos = 1 end
    local prefix = line_to_cursor:sub(prefixpos, #line_to_cursor)
    local cprefixpos = vim.fn.match(prefix, '\\k*$')
    local cprefix = prefix:sub(cprefixpos + 1, #prefix)
    local tick = vim.b.changedtick
    repl.complete(prefix, function(data)
      if not data.ok then return end
      local pos2 = vim.api.nvim_win_get_cursor(0)
      if pos[1] ~= pos2[1] or pos[2] ~= pos2[2] then return end
      if tick ~= vim.b.changedtick then return end
      vim.fn.complete(prefixpos + cprefixpos, data.ok[1])
    end)
    return -3
  end
  return {words={},refresh=false}
end

return {setup=setup}
