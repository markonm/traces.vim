if !exists('##CmdlineEnter') || exists('g:loaded_traces_plugin') || !has('timers') || &cp
  finish
endif
let g:loaded_traces_plugin = 1

let s:cpo_save = &cpo
set cpo-=C

let g:traces_enabled = get(g:, 'traces_enabled', 1)
let g:traces_preserve_view_state = get(g:, 'traces_preserve_view_state')
let g:traces_substitute_preview  = get(g:, 'traces_substitute_preview', 1)
let g:traces_skip_modifiers      = get(g:, 'traces_skip_modifiers', 1)
let s:view                       = {}

function! s:track_cmdl(...) abort
  let current_cmdl = getcmdline()
  if get(s:, 'previous_cmdl', '') !=# current_cmdl
    let s:previous_cmdl = current_cmdl
    call traces#init(current_cmdl, s:view)
  endif
endfunction

function! s:cmdline_changed() abort
  if exists('s:start_init_timer')
    call timer_stop(s:start_init_timer)
  endif
  let s:start_init_timer = timer_start(1, {_-> traces#init(getcmdline(), s:view)})
endfunction

function! s:create_cmdl_changed_au(...) abort
  augroup traces_augroup_cmdline_changed
    autocmd!
    autocmd CmdlineChanged : call s:cmdline_changed()
  augroup END
  " necessary when entering command line that has already been populated with
  " text from mappings
  call s:cmdline_changed()
endfunction

function! s:t_start() abort
  if !g:traces_enabled || mode(1) =~# '^c.'
    return
  endif
  if exists('##CmdlineChanged')
    let s:track_cmdl_timer = timer_start(30,function('s:create_cmdl_changed_au'))
  else
    let s:track_cmdl_timer = timer_start(30,function('s:track_cmdl'),{'repeat':-1})
  endif
endfunction

function! s:t_stop() abort
  if exists('s:previous_cmdl')
    unlet s:previous_cmdl
  endif
  if exists('s:track_cmdl_timer')
    call timer_stop(s:track_cmdl_timer)
    unlet s:track_cmdl_timer
  endif
  if exists('s:start_init_timer')
    call timer_stop(s:start_init_timer)
    unlet s:start_init_timer
  endif
  augroup traces_augroup_cmdline_changed
    autocmd!
  augroup END
endfunction

silent! cnoremap <unique> <expr> <c-r><c-w> traces#check_b() ? traces#get_cword() : "\<c-r>\<c-w>"
silent! cnoremap <unique> <expr> <c-r><c-a> traces#check_b() ? traces#get_cWORD() : "\<c-r>\<c-a>"
silent! cnoremap <unique> <expr> <c-r><c-f> traces#check_b() ? traces#get_cfile() : "\<c-r>\<c-f>"
silent! cnoremap <unique> <expr> <c-r><c-p> traces#check_b() ? traces#get_pfile() : "\<c-r>\<c-p>"

silent! cnoremap <unique> <expr> <c-r><c-r><c-w> traces#check_b() ? "\<c-r>\<c-r>=traces#get_cword()\<cr>" : "\<c-r>\<c-r>\<c-w>"
silent! cnoremap <unique> <expr> <c-r><c-r><c-a> traces#check_b() ? "\<c-r>\<c-r>=traces#get_cWORD()\<cr>" : "\<c-r>\<c-r>\<c-a>"
silent! cnoremap <unique> <expr> <c-r><c-r><c-f> traces#check_b() ? "\<c-r>\<c-r>=traces#get_cfile()\<cr>" : "\<c-r>\<c-r>\<c-f>"
silent! cnoremap <unique> <expr> <c-r><c-r><c-p> traces#check_b() ? "\<c-r>\<c-r>=traces#get_pfile()\<cr>" : "\<c-r>\<c-r>\<c-p>"

silent! cnoremap <unique> <expr> <c-r><c-o><c-w> traces#check_b() ? "\<c-r>\<c-r>=traces#get_cword()\<cr>" : "\<c-r>\<c-o>\<c-w>"
silent! cnoremap <unique> <expr> <c-r><c-o><c-a> traces#check_b() ? "\<c-r>\<c-r>=traces#get_cWORD()\<cr>" : "\<c-r>\<c-o>\<c-a>"
silent! cnoremap <unique> <expr> <c-r><c-o><c-f> traces#check_b() ? "\<c-r>\<c-r>=traces#get_cfile()\<cr>" : "\<c-r>\<c-o>\<c-f>"
silent! cnoremap <unique> <expr> <c-r><c-o><c-p> traces#check_b() ? "\<c-r>\<c-r>=traces#get_pfile()\<cr>" : "\<c-r>\<c-o>\<c-p>"

augroup traces_augroup
  autocmd!
  autocmd CmdlineEnter,CmdwinLeave : call s:t_start()
  autocmd CmdlineLeave,CmdwinEnter : call s:t_stop()
  autocmd CmdlineLeave : if mode(1) is 'c' | call traces#cmdl_leave() | endif
  " s:view is used to restore correct view when entering command line from
  " visual mode
  autocmd CursorMoved * let s:view = extend(winsaveview(), {'mode': mode()})

  " https://github.com/vim/vim/commit/b0acacd767a2b0618a7f3c08087708f4329580d0
  if has("patch-8.1.0271")
    autocmd CmdlineEnter,CmdwinLeave : let s:incsearch = &incsearch
          \| noautocmd let &incsearch = 0
    autocmd CmdlineLeave,CmdwinEnter : noautocmd let &incsearch = s:incsearch
  endif
augroup END

highlight default link TracesSearch Search

let &cpo = s:cpo_save
unlet s:cpo_save
