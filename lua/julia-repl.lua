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
      print('ERROR: orphan response: '..response)
    end
  end

  local repl = vim.fn.sockconnect("tcp", host..":"..port, {
    on_data = function(repl, data, name)
      if #data == 1 and data[1] == '' then -- EOF
        if #buf > 0 then
          on_response(table.concat(buf, ''))
          buf = {}
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

  function complete(prefix, callback)
    id = id + 1
    data = {type="complete",id=id,full=prefix,partial=prefix}
    callbacks[id] = callback
    vim.fn.chansend(repl, vim.fn.json_encode(data))
    vim.fn.chansend(repl, "\n")
  end

  function eval(code, callback)
    id = id + 1
    data = {type="eval",id=id,code=code}
    callbacks[id] = callback
    vim.fn.chansend(repl, vim.fn.json_encode(data))
    vim.fn.chansend(repl, "\n")
  end

  function input(code, callback)
    id = id + 1
    data = {type="input",id=id,code=code}
    callbacks[id] = callback
    vim.fn.chansend(repl, vim.fn.json_encode(data))
    vim.fn.chansend(repl, "\n")
  end

  function help(symbol, callback)
    symbol = vim.fn.json_encode(symbol)
    eval("eval(REPL.helpmode("..symbol.."))", callback)
  end

  function close()
    vim.fn.chanclose(repl)
  end

  return {eval=eval,input=input,complete=complete,help=help,close=close}
end

function setup()
  if vim.b.julia_repl ~= nil then
    vim.b.julia_repl.close()
  end
  vim.b.julia_repl = connect {host = "localhost", port = 2345}
  vim.api.nvim_buf_set_option(0, 'omnifunc', 'v:lua.julia_repl_comp')
end

function _G.julia_repl_send(code)
  local repl = vim.b.julia_repl
  if repl == nil then
    error("Julia REPL is not connected")
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
    print(vim.inspect {prefixpos = prefixpos, prefix = prefix})
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
