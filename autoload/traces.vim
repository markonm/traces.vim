let s:cpo_save = &cpo
set cpo&vim

let s:timeout = get(g:, 'traces_timeout', 1000)
let s:timeout = s:timeout > 200 ? s:timeout : 200
let s:s_timeout = get(g:, 'traces_search_timeout', 500)
let s:s_timeout = s:s_timeout > s:timeout - 100 ? s:timeout - 100 : s:s_timeout

let s:cmd_pattern = '\v\C^%('
                \ . 'g%[lobal][[:alnum:]]@!\!=|'
                \ . 's%[ubstitute][[:alnum:]]@!|'
                \ . 'sm%[agic][[:alnum:]]@!|'
                \ . 'sno%[magic][[:alnum:]]@!|'
                \ . 'sor%[t][[:alnum:]]@!\!=|'
                \ . 'v%[global][[:alnum:]]@!'
                \ . ')'

let s:buf = {}

function! s:trim(...) abort
  if a:0 == 2
    let a:1[0] = strpart(a:1[0], a:2)
  else
    let a:1[0] = substitute(a:1[0], '^\s\+', '', '')
  endif
endfunction

function! s:parse_range(range, cmdl) abort
  let specifier = {}
  let specifier.addresses = []

  let while_limit = 0
  while 1
    " address part
    call s:trim(a:cmdl)
    let entry = {}
    " regexp for pattern specifier
    let pattern = '/%(\\.|/@!&.)*/=|\?%(\\.|\?@!&.)*\?='
    if !len(specifier.addresses)
      " \& is not supported
      let address = matchstrpos(a:cmdl[0], '\v^%(\d+|\.|\$|\%|\*|''.|'. pattern . '|\\\/|\\\?)')
    else
      let address = matchstrpos(a:cmdl[0], '\v^%(' . pattern . ')' )
    endif
    if address[2] != -1
      call s:trim(a:cmdl, address[2])
      let entry.str = address[0]
    endif

    " offset
    call s:trim(a:cmdl)
    let offset = matchstrpos(a:cmdl[0], '\m^\%(\d\|\s\|+\|-\)\+')
    if offset[2] != -1
      call s:trim(a:cmdl, offset[2])
      let entry.offset = offset[0]
    endif

    " add first address
    if address[2] != -1 || offset[2] != -1
      " if offset is present but specifier is missing add '.' specifier
      if !has_key(entry, 'str')
        let entry.str = '.'
      endif
      call add(specifier.addresses, entry)
    else
      " stop trying if previous attempt was unsuccessful
      break
    endif
    let while_limit += 1 | if while_limit == 1000
          \ | echoerr 'infinite loop' | break | endif
  endwhile

  " delimiter
  call s:trim(a:cmdl)
  let delimiter = matchstrpos(a:cmdl[0], '\m^\%(,\|;\)')
  if delimiter[2] != -1
    call s:trim(a:cmdl, delimiter[2])
    let specifier.delimiter = delimiter[0]
  endif

  " add when addresses or delimiter are found or when one specifier is
  " already known
  if !empty(specifier.addresses) || delimiter[2] != -1 || !empty(a:range)
    " specifiers are not given but delimiter is present
    if empty(specifier.addresses)
      call add(specifier.addresses, { 'str': '.' })
    endif
    call add(a:range, specifier)
  endif

  if delimiter[2] != -1
    try
      return s:parse_range(a:range, a:cmdl)
    catch /^Vim\%((\a\+)\)\=:E132/
      return []
    endtry
  else
    return a:range
  endif
endfunction

" five cases (+11 -11 11 -- ++)
function! s:offset_to_num(string) abort
  let offset = 0
  let copy = a:string
  let input = [copy]
  let pattern = '\m^\%(+\d\+\|-\d\+\|\d\+\|-\+\ze-\d\|+\+\ze+\d\|-\+\|+\+\)'

  let while_limit = 0
  while !empty(input[0])
    call s:trim(input)
    let part = matchstrpos(input[0], pattern)
    call s:trim(input, part[2])

    if part[0] =~# '+\d\+'
      let offset += str2nr(matchstr(part[0], '\d\+'))
    elseif part[0] =~# '-\d\+'
      let offset -= str2nr(matchstr(part[0], '\d\+'))
    elseif part[0] =~# '\d\+'
      let offset += str2nr(part[0])
    elseif part[0] =~# '+\+'
      let offset += strchars(part[0])
    elseif part[0] =~# '-\+'
      let offset -= strchars(part[0])
    endif

    let while_limit += 1 | if while_limit == 1000
          \ | echoerr 'infinite loop' | break | endif
  endwhile

  return offset
endfunction

function! s:search(args, last_pos, shouldCache) abort
  if !has_key(s:buf[s:nr].cache, 'patterns')
    let s:buf[s:nr].cache.patterns = {}
  endif
  let patterns = s:buf[s:nr].cache.patterns
  let key = join(a:args) . a:last_pos
  if has_key(patterns, key)
    return patterns[key]
  endif
  silent! let pos = call('search', a:args)
  if a:shouldCache
    let patterns[key] = pos
  endif
  return pos
endfunction

function! s:address_to_num(address, last_pos) abort
  let result = {}
  let result.range = []
  let result.valid = 1
  let result.regex = ''
  let s:entire_file  = 0

  if     a:address.str =~# '^\d\+'
    let lnum = str2nr(a:address.str)
    call add(result.range, lnum)

  elseif a:address.str ==# '.'
    call add(result.range, a:last_pos)

  elseif a:address.str ==# '$'
    call add(result.range, getpos('$')[1])

  elseif a:address.str ==# '%'
    call add(result.range, 1)
    call add(result.range, getpos('$')[1])
    let s:entire_file = 1

  elseif a:address.str ==# '*'
    call add(result.range, getpos('''<')[1])
    call add(result.range, getpos('''>')[1])
    if match(&cpoptions, '\*') != -1
      let result.valid = 0
    endif
    let s:buf[s:nr].show_range = 1

  elseif a:address.str =~# '^''.'
    call cursor(a:last_pos, 1)
    let mark_position = getpos(a:address.str)
    if mark_position[1]
      call add(result.range, mark_position[1])
    else
      let result.valid = 0
    endif
    let s:buf[s:nr].show_range = 1

  elseif a:address.str[0] is '/'
    let closed = a:address.str =~# '\v%([^\\]\\)@<!\/$'
    let pattern = closed ? a:address.str[1:-2] : a:address.str[1:]
    if closed
      if empty(pattern)
        let pattern = s:last_pattern
      else
        let s:last_pattern = pattern
      endif
    endif
    call cursor(a:last_pos + 1, 1)
    if a:last_pos is line('$')
      if &wrapscan
        call cursor(1, 1)
      else
        let result.valid = 0
      endif
    endif
    let s:buf[s:nr].show_range = 1
    let query = s:search([pattern, 'nc', 0, s:s_timeout], a:last_pos, closed)
    if !query | let result.valid = 0 | endif
    if !closed | let result.regex = pattern | endif
    call add(result.range, query)

  elseif a:address.str[0] is '?'
    let closed = a:address.str =~# '\v%([^\\]\\)@<!\?$'
    let pattern = closed ? a:address.str[1:-2] : a:address.str[1:]
    let pattern = substitute(pattern, '\\?', '?', '')
    if closed
      if empty(pattern)
        let pattern = s:last_pattern
      else
        let s:last_pattern = pattern
      endif
    endif
    call cursor(a:last_pos, 1)
    let s:buf[s:nr].show_range = 1
    let query = s:search([pattern, 'nb', 0, s:s_timeout], a:last_pos, closed)
    if !query | let result.valid = 0 | endif
    if !closed | let result.regex = pattern | endif
    call add(result.range, query)

  elseif a:address.str ==# '\/'
    call cursor(a:last_pos + 1, 1)
    if a:last_pos is line('$')
      if &wrapscan
        call cursor(1, 1)
      else
        let result.valid = 0
      endif
    endif
    let query = s:search([s:last_pattern, 'nc', 0, s:s_timeout], a:last_pos, 1)
    if !query | let result.valid = 0 | endif
    call add(result.range, query)
    let s:buf[s:nr].show_range = 1

  elseif a:address.str ==# '\?'
    call cursor(a:last_pos, 1)
    let query = s:search([s:last_pattern, 'nb', 0, s:s_timeout], a:last_pos, 1)
    if !query | let result.valid = 0 | endif
    call add(result.range, query)
    let s:buf[s:nr].show_range = 1
  endif

  if !empty(result.range)
    " add offset
    if has_key(a:address, 'offset') && !s:entire_file
      let result.range[0] += s:offset_to_num(a:address.offset)
    endif

    " treat specifier 0 as 1
    if result.range[0] == 0
      let result.range[0] = 1
    endif

    " check if range exceeds file limits
    if result.range[0] > line('$') || result.range[0] < 0
      let result.valid = 0
    endif
  endif

  return result
endfunction

function! s:evaluate_range(range_structure) abort
  let result = { 'range': [], 'pattern': '', 'end': ''}
  let s:range_valid = 1
  let pos = s:buf[s:nr].cur_init_pos[0]

  for specifier in a:range_structure
    let tmp_pos = pos
    let specifier_result = []

    for address in specifier.addresses
      " skip empty unclosed pattern specifier when range is empty otherwise
      " substitute it with current position
      if address.str =~# '^[?/]$'
        let s:buf[s:nr].show_range = 1
        if empty(result.range)
          break
        endif
        let address.str = '.'
      endif
      let query = s:address_to_num(address, tmp_pos)
      " % specifier doesn't accept additional addresses
      if !query.valid || len(query.range) == 2 && len(specifier.addresses) > 1
        let s:range_valid = 0
        break
      endif
      let tmp_pos = query.range[-1]
      let specifier_result = deepcopy(query.range)
      let result.pattern = query.regex
    endfor
    if !s:range_valid
      break
    endif

    call extend(result.range, specifier_result)
    if exists('specifier.delimiter')
      let s:specifier_delimiter = 1
    endif
    if get(specifier, 'delimiter') is# ';'
      let pos = result.range[-1]
    endif
  endfor

  if !empty(result.range)
    let result.end = result.range[-1]
    if len(result.range) == 1
      call extend(result.range, result.range)
    else
      let result.range = result.range[-2:-1]
      if result.range[-1] < result.range[-2]
        let temp = result.range[-2]
        let result.range[-2] = result.range[-1]
        let result.range[-1] = temp
      endif
    endif
  endif

  return s:range_valid ? result : { 'range': [], 'pattern': '', 'end': '' }
endfunction

function! s:get_selection_regexp(range) abort
  if empty(a:range)
    return ''
  endif
  let pattern = '\%>' . (a:range[-2] - 1) . 'l\%<' . (a:range[-1]  + 1) . 'l'
  if &listchars =~# 'eol:.'
    let pattern .= '\_.'
  else
    let pattern .= '\(.\|^\)'
  endif
  return pattern
endfunction

function! s:get_command(cmdl) abort
  call s:trim(a:cmdl)
  if !s:range_valid
    return ''
  endif
  let result = matchstrpos(a:cmdl[0], s:cmd_pattern)
  if result[2] != -1
    call s:trim(a:cmdl, result[2])
    return result[0]
  endif
  return ''
endfunction

function! s:add_opt(pattern, cmdl) abort
  if empty(a:pattern) || !s:range_valid
        \ || empty(substitute(a:pattern, '\\[cCvVmM]', '', 'g'))
    return ''
  endif

  let option = ''

  " magic
  if has_key(a:cmdl, 'cmd') && a:cmdl.cmd.name =~# '\v^sm%[agic]$'
    let option = '\m'
  elseif  has_key(a:cmdl, 'cmd') && a:cmdl.cmd.name =~# '\v^sno%[magic]$'
    let option = '\M'
  elseif &magic
    let option = '\m'
  else
    let option = '\M'
  endif

  " case
  if &ignorecase
    if &smartcase
      if match(a:pattern, '\u') ==# -1
        let option .= '\c'
      else
        let option .= '\C'
      endif
    else
      let option .= '\c'
    endif
  endif

  return option . a:pattern
endfunction

function! s:add_hl_guard(pattern, range, type) abort
  if empty(a:pattern)
    return ''
  endif
  if a:type is 's'
    if empty(a:range)
      let start = s:buf[s:nr].cur_init_pos[0] - 1
      let end   = s:buf[s:nr].cur_init_pos[0] + 1
    else
      let start = a:range[-2] - 1
      let end   = a:range[-1] + 1
    endif
  elseif a:type is 'g'
    if empty(a:range)
      return  a:pattern
    else
      let start = a:range[-2] - 1
      let end   = a:range[-1] + 1
    endif
  elseif a:type is 'r'
    let start = a:range - 1
    let end   = a:range + 1
  endif

  let range = '\m\%>'. start .'l' . '\%<' . end . 'l'
  " group is necessary to contain pattern inside range when using branches (\|)
  let group_start = '\%('
  let group_end   = '\m\)'
  " add backslash to the end of pattern if it ends with odd number of
  " backslashes, this is required to properly close group
  if len(matchstr(a:pattern, '\\\+$')) % 2
    let group_end = '\' . group_end
  endif

  return range . group_start  . a:pattern . group_end
endfunction

function! s:parse_global(cmdl) abort
  call s:trim(a:cmdl.string)
  let pattern = '\v^([[:graph:]]&[^[:alnum:]\\"|])(%(\\.|.){-})%((\1)|$)'
  let args = {}
  let r = matchlist(a:cmdl.string[0], pattern)
  if len(r)
    let args.delimiter = r[1]
    let args.pattern   = s:add_opt((empty(r[2]) && !empty(r[3])) ? s:last_pattern : r[2], a:cmdl)
  endif
  return args
endfunction

function! s:parse_substitute(cmdl) abort
  call s:trim(a:cmdl.string)
  let pattern = '\v^([[:graph:]]&[^[:alnum:]\\"|])(%(\\.|\1@!&.)*)%((\1)%((%(\\.|\1@!&.)*)%((\1)([&cegiInp#lr]+)=)=)=)=$'
  let args = {}
  let r = matchlist(a:cmdl.string[0], pattern)
  if len(r)
    let args.delimiter        = r[1]
    let args.pattern_org      = (empty(r[2]) && !empty(r[3])) ? s:last_pattern : r[2]
    let args.pattern          = s:add_opt((empty(r[2]) && !empty(r[3])) ? s:last_pattern : r[2], a:cmdl)
    let args.string           = r[4]
    let args.last_delimiter   = r[5]
    let args.flags            = r[6]
  endif
  return args
endfunction

function! s:parse_sort(cmdl) abort
  call s:trim(a:cmdl.string)
  let pattern = '\v^.{-}([[:graph:]]&[^[:alnum:]\\"|])(%(\\.|.){-})%((\1)|$)'
  let args = {}
  let r = matchlist(a:cmdl.string[0], pattern)
  if len(r)
    let args.delimiter = r[1]
    let args.pattern   = s:add_opt((empty(r[2]) && !empty(r[3])) ? s:last_pattern : r[2], a:cmdl)
  endif
  return args
endfunction

function! s:parse_command(cmdl) abort
  let a:cmdl.cmd.name = s:get_command(a:cmdl.string)
  if a:cmdl.cmd.name =~# '\v^%(g%[lobal]\!=|v%[global])$'
    let a:cmdl.cmd.args = s:parse_global(a:cmdl)
  elseif a:cmdl.cmd.name =~# '\v^%(s%[ubstitute]|sm%[agic]|sno%[magic])$'
    let a:cmdl.cmd.args = s:parse_substitute(a:cmdl)
  elseif a:cmdl.cmd.name =~# '\v^%(sor%[t]\!=)$'
    let a:cmdl.cmd.args = s:parse_sort(a:cmdl)
  endif
endfunction

function! s:pos_pattern(pattern, range, delimiter, type) abort
  if g:traces_preserve_view_state || empty(a:pattern)
    return
  endif

  " restore position from cache
  if has_key(s:buf[s:nr].cache, 'pattern')
    let cache = s:buf[s:nr].cache.pattern
    if cache.state ==# a:
      call winrestview(cache.view)
      let s:moved = 1
      return
    endif
  endif

  let stopline = 0
  if len(a:range) > 1 && !get(s:, 'entire_file')
    if a:delimiter ==# '?'
      call cursor([a:range[-1], 1])
      call cursor([a:range[-1], col('$')])
      let stopline = a:range[-2]
    else
      call cursor([a:range[-2], 1])
      let stopline = a:range[-1]
    endif
  else
    call cursor(s:buf[s:nr].cur_init_pos)
    if a:type && empty(a:range)
      let stopline = s:buf[s:nr].cur_init_pos
    endif
  endif
  if a:delimiter ==# '?'
    silent! let position = search(a:pattern, 'cb', stopline, s:s_timeout)
  else
    silent! let position = search(a:pattern, 'c', stopline, s:s_timeout)
  endif
  if position !=# 0
    let s:moved = 1
  endif

  " save position to cache
  let cache = {}
  let cache.state = deepcopy(a:)
  let cache.view = winsaveview()
  let s:buf[s:nr].cache.pattern = cache
endfunction

function! s:pos_range(end, pattern) abort
  if g:traces_preserve_view_state || empty(a:end)
    return
  endif

  " restore position from cache
  if has_key(s:buf[s:nr].cache, 'range')
    let cache = s:buf[s:nr].cache.range
    if cache.state ==# a:
      call winrestview(cache.view)
      let s:moved = 1
      return
    elseif has_key(s:buf[s:nr].cache, 'pattern')
      " drop unvalid cache
      unlet s:buf[s:nr].cache.pattern
    endif
  endif

  if exists('s:buf[s:nr].pre_cmdl_view')
    if get(s:buf[s:nr].pre_cmdl_view, 'mode', '') =~# "^[vV\<C-V>]"
          \ && a:end > line('w$')
      unlet s:buf[s:nr].pre_cmdl_view.mode
      call winrestview(s:buf[s:nr].pre_cmdl_view)
    endif
    unlet s:buf[s:nr].pre_cmdl_view
  endif
  call cursor([a:end, 1])
  if !empty(a:pattern)
    silent! call search(a:pattern, 'c', a:end, s:s_timeout)
  endif
  let s:moved = 1

  " save position to cache
  let cache = {}
  let cache.state = deepcopy(a:)
  let cache.view = winsaveview()
  let s:buf[s:nr].cache.range = cache
endfunction

function! s:highlight(group, pattern, priority) abort
  let cur_win = s:buf[s:nr].cur_win
  if exists('s:buf[s:nr].win[cur_win].matches[a:group].pattern')
    if s:buf[s:nr].win[cur_win].matches[a:group].pattern ==# a:pattern
      return
    endif
  elseif empty(a:pattern)
    return
  endif
  if a:group ==# 'TracesSearch' || a:group ==# 'TracesReplace'
    noautocmd let &hlsearch = 0
  endif
  noautocmd let &winwidth = &winminwidth
  noautocmd let &winheight = &winminheight

  let windows = filter(win_findbuf(s:nr), {_, val -> win_id2win(val)})
  " skip minimized windows
  let windows = filter(windows, 'getwininfo(v:val)[0].height isnot 0'
        \ . ' && getwininfo(v:val)[0].width isnot 0')

  if empty(s:buf[s:nr].win)
    " save local options
    for id in windows
      let s:buf[s:nr].win[id] = {}
      let win = s:buf[s:nr].win[id]
      let win.options = {}
      let win.options.cursorcolumn = getwinvar(id, '&cursorcolumn')
      let win.options.cursorline = getwinvar(id, '&cursorline')
      let win.options.scrolloff = getwinvar(id, '&scrolloff')
      let win.options.conceallevel = getwinvar(id, '&conceallevel')
      let win.options.concealcursor = getwinvar(id, '&concealcursor')
    endfor
    " set local options
    for id in windows
      call setwinvar(id, '&' . 'cursorcolumn', 0)
      call setwinvar(id, '&' . 'cursorline', 0)
      if id isnot s:buf[s:nr].cur_win
        call setwinvar(id, '&' . 'scrolloff', 0)
      endif
    endfor
  endif

  " add matches
  for id in windows
    noautocmd call win_gotoid(id)
    let win = s:buf[s:nr].win[id]
    let win.matches = get(win, 'matches', {})
    if !exists('win.matches[a:group]')
      silent! let match_id = matchadd(a:group, a:pattern, a:priority)
      let win.matches[a:group] = {'match_id': match_id, 'pattern': a:pattern}
      let s:redraw_later = 1
      if a:group ==# 'Conceal'
        noautocmd let &l:conceallevel=2
        noautocmd let &l:concealcursor='c'
      endif
    else
      silent! call matchdelete(win.matches[a:group].match_id)
      silent! let match_id = matchadd(a:group, a:pattern, a:priority)
      let win.matches[a:group] = {'match_id': match_id, 'pattern': a:pattern}
      let s:redraw_later = 1
    endif
  endfor

  noautocmd call win_gotoid(s:buf[s:nr].cur_win)
endfunction

function! s:format_command(cmdl) abort
  let c = ''
  if len(a:cmdl.range.abs) == 0
    let c .= s:buf[s:nr].cur_init_pos[0]
  elseif len(a:cmdl.range.abs) == 1
    let c .= a:cmdl.range.abs[0]
  else
    if substitute(a:cmdl.cmd.args.pattern_org, '\\\\', '', 'g') =~# '\v(\\n|\\_\.|\\_\[|\\_[iIkKfFpPsSdDxXoOwWhHaAlLuU])'
      let c .= a:cmdl.range.abs[-2]
      let c .= ';'
      let c .= a:cmdl.range.abs[-1]
    else
      let c .= max([a:cmdl.range.abs[-2], line("w0")])
      let c .= ';'
      let c .= min([a:cmdl.range.abs[-1], line("w$")])
    end
  endif
  let c .= a:cmdl.cmd.name
  let c .= a:cmdl.cmd.args.delimiter
  let c .= a:cmdl.cmd.args.pattern_org
  let c .= a:cmdl.cmd.args.delimiter
  let s_mark = s:buf[s:nr].s_mark
  if a:cmdl.cmd.args.string =~# '^\\='
    let c .= printf("\\='%s' . printf('%%s', %s) . '%s'",
          \ s_mark, empty(a:cmdl.cmd.args.string[2:]) ?
          \ '''''' : a:cmdl.cmd.args.string[2:], s_mark)
  else
    " make ending single backslash literal or else it will escape s_mark
    if substitute(a:cmdl.cmd.args.string, '\\\\', '', 'g') =~# '\\$'
      let c .= s_mark . a:cmdl.cmd.args.string . '\' . s_mark
    else
      let c .= s_mark . a:cmdl.cmd.args.string . s_mark
    endif
  endif
  let c .= a:cmdl.cmd.args.delimiter
  let c .= substitute(a:cmdl.cmd.args.flags, '[^giI]', '', 'g')
  return c
endfunction

function! s:preview_substitute(cmdl) abort
  if empty(a:cmdl.cmd.args)
    return
  endif

  let ptrn  = a:cmdl.cmd.args.pattern
  let str   = a:cmdl.cmd.args.string
  let range = a:cmdl.range.abs
  let dlm   = a:cmdl.cmd.args.delimiter

  call s:pos_pattern(ptrn, range, dlm, 1)

  if !g:traces_substitute_preview || &readonly || !&modifiable || empty(str)
    call s:highlight('TracesSearch', s:add_hl_guard(ptrn, range, 's'), 101)
    return
  endif

  call s:save_undo_history()

  if s:buf[s:nr].undo_file is 0
    call s:highlight('TracesSearch', s:add_hl_guard(ptrn, range, 's'), 101)
    return
  endif

  let cmd = 'noautocmd keepjumps keeppatterns ' . s:format_command(a:cmdl)
  let tick = b:changedtick

  let lines = line('$')
  let view = winsaveview()
  let ul = &l:undolevels
  noautocmd let &l:undolevels = 0
  silent! execute cmd
  noautocmd let &l:undolevels = ul

  if tick == b:changedtick
    return
  endif

  let s:buf[s:nr].changed = 1

  call winrestview(view)
  let s:redraw_later = 1
  let lines = lines - line('$')

  if lines && !get(s:, 'entire_file') && !empty(range)
    if len(range) == 1
      call add(range, range[0])
    endif
    let range[-1] -= lines
    call s:highlight('Visual', s:get_selection_regexp(range), 100)
  endif
  call s:highlight('TracesSearch', '', 101)
  call s:highlight('TracesReplace', s:buf[s:nr].s_mark . '\_.\{-}' . s:buf[s:nr].s_mark, 101)
  call s:highlight('Conceal', s:buf[s:nr].s_mark . '\|' . s:buf[s:nr].s_mark, 102)
endfunction

function! s:preview_global(cmdl) abort
  if empty(a:cmdl.range.specifier) && has_key(a:cmdl.cmd.args, 'pattern')
    let pattern = a:cmdl.cmd.args.pattern
    let range = a:cmdl.range.abs
    call s:highlight('TracesSearch', s:add_hl_guard(pattern, range, 'g'), 101)
    call s:pos_pattern(pattern, range, a:cmdl.cmd.args.delimiter, 0)
  endif
endfunction

function! s:preview_sort(cmdl) abort
  if empty(a:cmdl.range.specifier) && has_key(a:cmdl.cmd.args, 'pattern')
    let pattern = a:cmdl.cmd.args.pattern
    let range = a:cmdl.range.abs
    call s:highlight('TracesSearch', s:add_hl_guard(pattern, range, 'g'), 101)
    call s:pos_pattern(pattern, range, a:cmdl.cmd.args.delimiter, 0)
  endif
endfunction

function! s:cmdl_enter(view) abort
  let s:buf[s:nr] = {}
  let s:buf[s:nr].cache = {}
  let s:buf[s:nr].view = winsaveview()
  let s:buf[s:nr].show_range = 0
  let s:buf[s:nr].duration = 0
  let s:buf[s:nr].hlsearch = &hlsearch
  let s:buf[s:nr].cword = expand('<cword>')
  let s:buf[s:nr].cWORD = expand('<cWORD>')
  let s:buf[s:nr].cfile = expand('<cfile>')
  let s:buf[s:nr].cur_init_pos = [line('.'), col('.')]
  let s:buf[s:nr].seq_last = undotree().seq_last
  let s:buf[s:nr].empty_undotree = empty(undotree().entries)
  let s:buf[s:nr].changed = 0
  let s:buf[s:nr].cmdheight = &cmdheight
  let s:buf[s:nr].redraw = 1
  let s:buf[s:nr].s_mark = (&encoding == 'utf-8' ? "\uf8b4" : '' )
  let s:buf[s:nr].winrestcmd = winrestcmd()
  let s:buf[s:nr].cur_win = win_getid()
  let s:buf[s:nr].alt_win = win_getid(winnr('#'))
  let s:buf[s:nr].winwidth = &winwidth
  let s:buf[s:nr].winheight = &winheight
  let s:buf[s:nr].pre_cmdl_view = a:view
  let s:buf[s:nr].win = {}
  call s:save_marks()
endfunction

function! traces#cmdl_leave() abort
  let s:nr = bufnr('%')
  if !exists('s:buf[s:nr]')
    return
  endif

  call s:restore_undo_history()

  " clear highlights
  for id in keys(s:buf[s:nr].win)
    noautocmd call win_gotoid(id)
    for group in keys(get(s:buf[s:nr].win[id], 'matches', {}))
      silent! call matchdelete(s:buf[s:nr].win[id].matches[group].match_id)
    endfor
  endfor

  " restore previous window <c-w>p
  if bufname('%') !=# '[Command Line]'
    noautocmd call win_gotoid(s:buf[s:nr].alt_win)
    noautocmd call win_gotoid(s:buf[s:nr].cur_win)
  endif

  " restore local options
  for id in keys(s:buf[s:nr].win)
    for option in keys(get(s:buf[s:nr].win[id], 'options', {}))
      call setwinvar(id, '&' . option, s:buf[s:nr].win[id].options[option])
    endfor
  endfor

  " restore global options
  if &hlsearch !=# s:buf[s:nr].hlsearch
    noautocmd let &hlsearch = s:buf[s:nr].hlsearch
  endif
  if &cmdheight !=# s:buf[s:nr].cmdheight
    noautocmd let &cmdheight = s:buf[s:nr].cmdheight
  endif
  if &winwidth isnot s:buf[s:nr].winwidth
    noautocmd let &winwidth = s:buf[s:nr].winwidth
  endif
  if &winheight isnot s:buf[s:nr].winheight
    noautocmd let &winheight = s:buf[s:nr].winheight
  endif

  if winrestcmd() isnot s:buf[s:nr].winrestcmd
    noautocmd execute s:buf[s:nr].winrestcmd
  endif
  if winsaveview() !=# s:buf[s:nr].view
    call winrestview(s:buf[s:nr].view)
  endif

  unlet s:buf[s:nr]
endfunction

function! s:evaluate_cmdl(string) abort
  let cmdl                 = {}
  let cmdl.string          = a:string
  let r                    = s:evaluate_range(s:parse_range([], cmdl.string))
  let cmdl.range           = {}
  let cmdl.range.abs       = r.range
  let cmdl.range.end       = r.end
  let cmdl.range.pattern   = s:get_selection_regexp(r.range)
  let cmdl.range.specifier = s:add_hl_guard(s:add_opt(r.pattern, cmdl), r.end, 'r')

  let cmdl.cmd             = {}
  let cmdl.cmd.args        = {}
  call s:parse_command(cmdl)

  return cmdl
endfunction

function! s:save_marks() abort
  if !exists('s:buf[s:nr].marks')
    let types = ['[', ']']
    let s:buf[s:nr].marks  = {}
    for mark in types
      let s:buf[s:nr].marks[mark] = getpos("'" . mark)
    endfor
  endif
endfunction

function! s:restore_marks() abort
  if exists('s:buf[s:nr].marks')
    for mark in keys(s:buf[s:nr].marks)
      call setpos("'" . mark, s:buf[s:nr].marks[mark])
    endfor
  endif
endfunction

function! s:save_undo_history() abort
  if exists('s:buf[s:nr].undo_file')
    return
  endif
  if bufname('%') ==# '[Command Line]' || s:buf[s:nr].empty_undotree
    let s:buf[s:nr].undo_file = 1
    return
  endif
  let s:buf[s:nr].undo_file = tempname()
  let time = reltime()
  noautocmd silent execute 'wundo ' . s:buf[s:nr].undo_file
  let s:wundo_time = reltimefloat(reltime(time)) * 1000
  if !filereadable(s:buf[s:nr].undo_file)
    let s:buf[s:nr].undo_file = 0
    return
  endif
endfunction

function! s:restore_undo_history() abort
  if s:buf[s:nr].changed
    noautocmd keepjumps silent undo
    call s:restore_marks()
  endif

  if type(get(s:buf[s:nr], 'undo_file')) isnot v:t_string
    return
  endif

  if has('nvim')
    " can't use try/catch on Neovim inside CmdlineLeave
    " https://github.com/neovim/neovim/issues/7876
    silent! execute 'noautocmd rundo ' . s:buf[s:nr].undo_file
    if undotree().seq_last !=# s:buf[s:nr].seq_last
      echohl WarningMsg
      echom 'traces.vim - undo history could not be restored'
      echohl None
    endif
  else
    try
      silent execute 'noautocmd rundo ' . s:buf[s:nr].undo_file
    catch
      echohl WarningMsg
      echom 'traces.vim - ' . v:exception
      echohl None
    endtry
  endif
  call delete(s:buf[s:nr].undo_file)
endfunction

function! s:adjust_cmdheight() abort
  let len = strwidth(strtrans(getcmdline())) + 2
  let col = &columns
  let height = &cmdheight
  if col * height < len
    noautocmd let &cmdheight=(len / col) + 1
    redraw
  elseif col * (height - 1) >= len && height > s:buf[s:nr].cmdheight
    noautocmd let &cmdheight=max([(len / col), s:buf[s:nr].cmdheight])
    redraw
  endif
endfunction

function! s:skip_modifiers(cmdl) abort
  let cmdl = a:cmdl
  " skip leading colons
  let cmdl = substitute(cmdl, '\v^[[:space:]:]+', '', '')
  " skip modifiers
  let pattern = '\v^%(%('
        \ . 'sil%[ent]%(\!|\H@=)|'
        \ . 'verb%[ose]\H@=|'
        \ . 'noa%[utocmd]\H@=|'
        \ . 'loc%[kmarks]\H@=|'
        \ . 'keepp%[atterns]\H@=|'
        \ . 'keepa%[lt]\H@=|'
        \ . 'keepj%[umps]\H@=|'
        \ . 'kee%[pmarks]\H@='
        \ . ')\s*)+'
  let cmdl = substitute(cmdl, pattern, '', '')

  if g:traces_skip_modifiers
    " skip *do modifiers
    let cmdl = substitute(cmdl,
          \ '\v^%(%(%(\d+|\.|\$|\%)\s*[,;]=\s*)+)=\s*%(cdo|cfdo|ld%[o]|lfdo'
          \ . '|bufd%[o]|tabd%[o]\!@!|argdo|wind%[o]\!@!)%(\!|\H@=)\s*', '', '')
    " skip modifiers again
    let cmdl = substitute(cmdl, pattern, '', '')
  endif

  return cmdl
endfunction

function! traces#init(cmdl, view) abort
  if &buftype ==# 'terminal' || (has('nvim') && !empty(&inccommand))
    if exists('s:track_cmdl_timer')
      call timer_stop(s:track_cmdl_timer)
    endif
    return
  endif

  let s:nr =  bufnr('%')
  if !exists('s:buf[s:nr]')
    call s:cmdl_enter(a:view)
  endif

  let s:redraw_later = 0
  let s:moved       = 0
  let s:last_pattern = @/
  let s:specifier_delimiter = 0
  let s:wundo_time = 0

  if s:buf[s:nr].duration < s:timeout
    let start_time = reltime()
  endif

  if s:buf[s:nr].changed
    let view = winsaveview()
    noautocmd keepjumps silent undo
    let s:buf[s:nr].changed = 0
    let s:redraw_later = 1
    call s:restore_marks()
    call winrestview(view)
  endif

  if s:buf[s:nr].duration < s:timeout
    let cmdl = s:evaluate_cmdl([s:skip_modifiers(a:cmdl)])
    " range preview
    if (!empty(cmdl.cmd.name) && !empty(cmdl.cmd.args) || s:buf[s:nr].show_range
          \ || s:specifier_delimiter && g:traces_num_range_preview)
          \ && !get(s:, 'entire_file')
      call s:highlight('Visual', cmdl.range.pattern, 100)
      if empty(cmdl.cmd.name)
        call s:highlight('TracesSearch', cmdl.range.specifier, 101)
      endif
      call s:pos_range(cmdl.range.end, cmdl.range.specifier)
    else
      " clear unnecessary range hl
      call s:highlight('Visual', '', 100)
    endif

    " cmd preview
    if cmdl.cmd.name =~# '\v^%(s%[ubstitute]|sm%[agic]|sno%[magic])$'
      call s:preview_substitute(cmdl)
    elseif cmdl.cmd.name =~# '\v^%(g%[lobal]\!=|v%[global])$'
      call s:preview_global(cmdl)
    elseif cmdl.cmd.name =~# '\v^%(sor%[t]\!=)$'
      call s:preview_sort(cmdl)
    endif

    if empty(cmdl.cmd.name) && empty(cmdl.range.specifier)
          \ || !empty(cmdl.cmd.name) && empty(cmdl.cmd.args)
      call s:highlight('TracesSearch', '', 101)
    endif
  endif

  " move to starting position if necessary
  if !s:moved && winsaveview() != s:buf[s:nr].view && !wildmenumode()
    call winrestview(s:buf[s:nr].view)
  endif

  " redraw screen if necessary
  if s:redraw_later
    call s:adjust_cmdheight()
    if has('nvim')
      redraw
    else
      " https://github.com/markonm/traces.vim/issues/17
      " if Vim is missing CmdlineChanged, use explicit redraw only at the
      " start of preview or else it is going to be slow
      if exists('##CmdlineChanged') || s:buf[s:nr].redraw
        redraw
        let s:buf[s:nr].redraw = 0
      else
        call winline()
      endif
      " after patch 8.0.1449, necessary for linux cui, otherwise highlighting
      " is not drawn properly, fixed by 8.0.1476
      if has('unix') && !has('gui_running') && has("patch-8.0.1449") && !has("patch-8.0.1476")
        silent! call feedkeys(getcmdpos() is 1 ? "\<right>\<left>" : "\<left>\<right>", 'tn')
      endif
    endif
  endif

  if exists('start_time')
    let s:buf[s:nr].duration = reltimefloat(reltime(start_time)) * 1000 - s:wundo_time
  endif
endfunction

function! traces#get_cword() abort
  return s:buf[s:nr].cword
endfunction

function! traces#get_cWORD() abort
  return s:buf[s:nr].cWORD
endfunction

function! traces#get_cfile() abort
  return s:buf[s:nr].cfile
endfunction

function! traces#get_pfile() abort
  let result = split(globpath(&path, s:buf[s:nr].cfile), '\n')
  if len(result) && len(s:buf[s:nr].cfile)
    return result[-1]
  endif
  return ''
endfunction

function! traces#check_b() abort
  let s:nr =  bufnr('%')
  if getcmdtype() == ':' && exists('s:buf[s:nr]')
    return 1
  endif
endfunction

let &cpo = s:cpo_save
unlet s:cpo_save
