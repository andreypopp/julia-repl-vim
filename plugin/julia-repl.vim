function! s:send_range(startline, endline) abort
  let rv = getreg('"')
  let rt = getregtype('"')
  silent exe a:startline . ',' . a:endline . 'yank'
  call v:lua.julia_repl_send(trim(@", "\n", 2))
  call setreg('"', rv, rt)
endfunction

function! s:send_op(type, ...) abort
  let sel_save = &selection
  let &selection = "inclusive"
  let rv = getreg('"')
  let rt = getregtype('"')

  if a:0  " Invoked from Visual mode, use '< and '> marks.
    silent exe "normal! `<" . a:type . '`>y'
  elseif a:type == 'line'
    silent exe "normal! '[V']y"
  elseif a:type == 'block'
    silent exe "normal! `[\<C-V>`]\y"
  else
    silent exe "normal! `[v`]y"
  endif

  call setreg('"', @", 'V')
  call v:lua.julia_repl_send(trim(@", "\n", 2))

  let &selection = sel_save
  call setreg('"', rv, rt)
endfunction

function! s:store_cur()
  let s:cur = winsaveview()
endfunction

function! s:restore_cur()
  if exists("s:cur")
    call winrestview(s:cur)
    unlet s:cur
  endif
endfunction

command -range -bar -nargs=0 JuliaREPLConnect
      \ lua require('julia-repl').setup()
command -range -bar -nargs=0 JuliaREPLSend
      \  call s:store_cur()
      \| call s:send_range(<line1>, <line2>)
      \| call s:restore_cur()
command -range -bar -nargs=0 JuliaREPLSendRegion
      \  call s:store_cur()
      \| call s:send_op(visualmode(), 1)
      \| call s:restore_cur()

nmap <leader>e :JuliaREPLSend<cr>
xmap <leader>e :JuliaREPLSendRegion<cr>
