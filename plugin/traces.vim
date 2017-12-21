if !exists('##CmdlineEnter') || exists("g:loaded_traces_plugin") || &cp
  finish
endif
let g:loaded_traces_plugin = 1

let s:cpo_save = &cpo
set cpo-=C

if !exists('g:traces_whole_file_range')
  let g:traces_whole_file_range = 0
endif

if !exists('g:traces_preserve_view_state')
  let g:traces_preserve_view_state = 0
endif

function! s:trim(...) abort
  if a:0 == 2
    let a:1[0] = strcharpart(a:1[0], a:2)
  else
    let a:1[0] = substitute(a:1[0], '^\s\+', '', '')
  endif
endfunction

function! s:parse_range(range, cmdl) abort
  let specifier = {}
  let specifier.addresses = []

  let while_limit = 0
  let flag = 1
  while flag
    " address part
    call s:trim(a:cmdl)
    let entry = {}
    " regexp for pattern specifier
    let pattern = '/\%(\\/\|[^/]\)*/\=\|?\%(\\?\|[^?]\)*?\='
    if len(specifier.addresses) == 0
      " \& is not supported
      let address = matchstrpos(a:cmdl[0],
            \ '\m^\%(\d\+\|\.\|\$\|%\|\*\|''.\|'. pattern . '\|\\/\|\\?\)')
    else
      let address = matchstrpos(a:cmdl[0],
            \ '\m^\%(' . pattern . '\)' )
    endif
    if address[2] != -1
      call s:trim(a:cmdl, address[2])
      let entry.address = address[0]
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
      call add(specifier.addresses, entry)
    else
      " stop trying if previous attempt was unsuccessful
      let flag = 0
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
  if len(specifier.addresses) > 0  || delimiter[2] != -1
        \ || len(a:range) > 0
    call add(a:range, specifier)
  endif

  if delimiter[2] != -1
    return s:parse_range(a:range, a:cmdl)
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
  while input[0] !=# ''
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

function! s:mark_to_absolute(address, last_position, range_size) abort
  let result = {}
  let result.range = []
  let result.valid = 1
  let result.skip  = 0
  let result.regex = ''
  let s:keep_pos  = 0

  if has_key(a:address, 'address')

    if     a:address.address =~# '^\d\+'
      let lnum = str2nr(a:address.address)
      call add(result.range, lnum)

    elseif a:address.address ==  '.'
      call add(result.range, a:last_position)

    elseif a:address.address ==  '$'
      call add(result.range, getpos('$')[1])

    elseif a:address.address ==  '%'
      call add(result.range, 1)
      call add(result.range, getpos('$')[1])
      let s:keep_pos = 1

    elseif a:address.address ==  '*'
      call add(result.range, getpos('''<')[1])
      call add(result.range, getpos('''>')[1])
      if match(&cpoptions, '\*') != -1
        let result.valid = 0
      endif
      let s:show_range = 1

    elseif a:address.address =~# '^''.'
      let mark_position = getpos(a:address.address)
      if !mark_position[0]
        call add(result.range, mark_position[1])
      else
        let result.valid = 0
      endif
      let s:show_range = 1

    elseif a:address.address =~# '^/.*[^\\]/$\|^//$'
      let pattern = a:address.address
      let pattern = substitute(pattern, '^/', '', '')
      let pattern = substitute(pattern, '/$', '', '')
      call cursor(a:last_position + 1, 1)
      let s:show_range = 1
      silent! let query = search(pattern, 'nc')
      if query == 0
        let result.valid = 0
      endif
      call add(result.range, query)

    elseif a:address.address =~# '^?.*[^\\]?$\|^??$'
      let pattern = a:address.address
      let pattern = substitute(pattern, '^?', '', '')
      let pattern = substitute(pattern, '?$', '', '')
      let pattern = substitute(pattern, '\\?', '?', '')
      call cursor(a:last_position, 1)
      let s:show_range = 1
      silent! let query = search(pattern, 'nb')
      if query == 0
        let result.valid = 0
      endif
      call add(result.range, query)

    elseif a:address.address =~# '^/.*$'
      let pattern = a:address.address
      let pattern = substitute(pattern, '^/', '', '')
      call cursor(a:last_position + 1, 1)
      silent! let query = search(pattern, 'nc')

      " stay at the same position if pattern is not provided
      if len(pattern) == 0
        if a:range_size == 0
          let result.skip = 1
        endif
        call add(result.range, a:last_position)
      else
        call add(result.range, query)
      endif

      let s:show_range = 1
      let result.regex = pattern

    elseif a:address.address =~# '^?.*$'
      let pattern = a:address.address
      let pattern = substitute(pattern, '^?', '', '')
      let pattern = substitute(pattern, '\\?', '?', '')
      call cursor(a:last_position, 1)
      silent! let query = search(pattern, 'nb')

      " stay at the same position if pattern is not provided
      if len(pattern) == 0
        if a:range_size == 0
          let result.skip = 1
        endif
        call add(result.range, a:last_position)
      else
        call add(result.range, query)
      endif

      let s:show_range = 1
      let result.regex = pattern

    elseif a:address.address ==  '\/'
      let pattern = @/
      call cursor(a:last_position + 1, 1)
      silent! let query = search(pattern, 'nc')
      if query == 0
        let result.valid = 0
      endif
      call add(result.range, query)
      let s:show_range = 1

    elseif a:address.address ==  '\?'
      let pattern = @?
      call cursor(a:last_position, 1)
      silent! let query = search(pattern, 'nb')
      if query == 0
        let result.valid = 0
      endif
      call add(result.range, query)
      let s:show_range = 1
    endif

  else
    call add(result.range, a:last_position)
  endif

  " add offset
  if len(result.range) > 0 && !has_key(a:address, 'address')
    let result.range[0] = result.range[0] + s:offset_to_num(a:address.offset)
  elseif len(result.range) > 0 && has_key(a:address, 'offset') &&
     \ a:address.address !~# '%'
    let result.range[0] = result.range[0] + s:offset_to_num(a:address.offset)
  endif

  " treat specifier 0 as 1
  if exists('lnum') && result.range[0] == 0
    let result.range[0] = 1
  endif

  return result
endfunction

function! s:evaluate_range(range_structure) abort
  let last_delimiter = ''
  let result = { 'range': []}
  let valid = 1
  let last_position = getpos('.')[1]
  let result.pattern = ''

  for specifier in a:range_structure
    let entry = {}
    let entire_file = 0
    let use_temp_position = 0
    let specifier_result = []

    " specifiers are not given but delimiter is present
    if !len(specifier.addresses)
      call add(specifier.addresses, { 'address': '.' })
    endif

    for address in specifier.addresses
      let query = s:mark_to_absolute(address,
            \ use_temp_position ? temp_position : last_position, len(result.range))
      if query.valid
        let temp_position = query.range[len(query.range) - 1]
        let use_temp_position = 1
        if !query.skip
          call extend(specifier_result, query.range)
          let result.pattern = query.regex
        endif
        if len(query.range) == 2
          let entire_file = 1
        endif
      else
        let valid = 0
      endif
    endfor

    if has_key(specifier, 'delimiter')
      let last_delimiter = specifier.delimiter
    endif

    if len(specifier_result) != 0
      if entire_file
        call extend(result.range, specifier_result)
      elseif len(specifier_result)
        call add(result.range, specifier_result[len(specifier_result) - 1])
      endif

      if last_delimiter == ';'
        let last_position = result.range[len(result.range) - 1]
      endif
    endif
  endfor

  return valid ? result : { 'range' : [], 'pattern' : '' }
endfunction

function! s:get_selection_regexp(range) abort
  " don't draw selection if range is whole file or one line
  if len(a:range) == 0
    return ''
  endif

  if a:range[len(a:range) - 1] > line('$') || a:range[len(a:range) - 2] > line('$')
    return ''
  endif

  if len(a:range) == 1
    let pattern = '\m\%' . a:range[0] . 'l'
  else
    let pattern_start = a:range[len(a:range) - 2]
    let pattern_end = a:range[len(a:range) - 1]

    if pattern_end < pattern_start
      let temp = pattern_start
      let pattern_start = pattern_end
      let pattern_end = temp
    endif

    let pattern_start -= 1
    let pattern_end += 1
    let pattern = '\m\%<' . pattern_end . 'l\%>' . pattern_start . 'l'
  endif

  return pattern
endfunction

function! s:get_command(cmdl) abort
  call s:trim(a:cmdl)
  let result = matchstrpos(a:cmdl[0], '\m\w\+!\=\|[<>!#]')
  if result[2] != -1
    call s:trim(a:cmdl, result[2])

    if match(result[0], '\m^\<s\ze\%[ubstitute]\>') != -1
      return 's'
    elseif match(result[0], '\m^\<sno\ze\%[magic]\>') != -1
      return 'sno'
    elseif match(result[0], '\m^\<sm\ze\%[agic]\>') != -1
      return 'sm'
    elseif match(result[0], '\m^\<g\ze\%[lobal]!\=\>') != -1
      return 'g'
    elseif match(result[0], '\m^\<v\ze\%[global]\>') != -1
      return 'g'
    elseif match(result[0], '\m^\%(d\%[elete]\|j\%[oin]!\=\|<\|le\%[ft]\|>\|y\%[ank]\|co\%[py]\|m\%[ove]\|ce\%[nter]\|ri\%[ght]\|le\%[ft]\|sor\%[t]!\=\|!\|diffg\%[et]\|diffpu\%[t]\|w\%[rite]!\=\|up\%[date]!\=\|wq!\=\|x\%[it]!\=\|exi\%[t]!\=\|cal\%[l]\|foldd\%[oopen]\|folddoc\%[losed]\|lua\|luado\|luafile\|mz\%[scheme]\|mzf\%[ile]\|perld\%[o]\|py\%[thon]\|py\%[thon]\|pydo\|pyf\%[ile]\|rubyd\%[o]\|tc\%[l]\|tcld\%[o]\|r\%[ead]\|ma\%[rk]\|k\|ha\%[rdcopy]!\=\|is\%[earch]!\=\|il\%[ist]!\=\|ij\%[ump]!\=\|isp\%[lit]!\=\|ds\%[earch]!\=\|dli\%[st]!\=\|dj\%[ump]!\=\|dsp\%[lit]!\=\|ter\%[minal]\|p\%[rint]\|l\%[ist]\|nu\%[mber]\|#\|ps\%[earch]!\=\|norm\%[al]!\=\|c\%[hange]!\=\|fo\%[ld]\|foldo\%[pen]!\=\|foldc\%[lose]!\=\|a\%[ppend]!\=\|i\%[nsert]!\=\|=\|z\|z#\|t\)') != -1
      return 'c'
    else
      return ''
    endif
  endif
  return ''
endfunction

function! s:get_pattern(command, cmdl) abort
  call s:trim(a:cmdl)
  if get({'s': 1, 'sno': 1, 'sm': 1, 'g': 1}, a:command, 0)
    let delimiter = strcharpart(a:cmdl[0], 0, 1)
    if delimiter !~ '\W'
      return ''
    endif
    let regexp = '\m^' . delimiter . '\%(\\' . delimiter
          \ . '\|[^' . delimiter . ']\)*' . delimiter . '\='

    try
      let pattern = matchstrpos(a:cmdl[0], regexp)
    catch
      return ''
    endtry

    if pattern[2] != -1
      call s:trim(a:cmdl, pattern[2])
    endif
    let pattern = substitute(pattern[0], '^.', '', '')
    let pattern = substitute(pattern, '\%([^\\]\|^\)\zs' . delimiter . '$', '', '')
    if delimiter != '/'
      let pattern = substitute(pattern, '\\' . delimiter, delimiter, 'g')
    endif
    return pattern
  endif
  return ''
endfunction

function! s:get_pattern_regexp(command, range, pattern) abort
  if !len(a:pattern)
    return ''
  endif
  if !len(substitute(a:pattern, '\\[cCvVmM]', '', 'g'))
    return ''
  endif

  let option = ''

  " magic
  if a:command == 'sm'
    let option = '\m'
  elseif a:command == 'sno'
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

  let group_start = '\%('
  let group_end   = '\m\)'

  if get({'s': 1, 'sno': 1, 'sm': 1}, a:command, 0)
    if len(a:range) > 1
      let start = a:range[len(a:range) - 2]
      let end   = a:range[len(a:range) - 1]
      if end < start
        let temp = start
        let start = end
        let end = temp
      endif
      let start = start - 1
      let end   = end + 1
    elseif len(a:range) == 1
      let start = a:range[len(a:range) - 1] - 1
      let end   = a:range[len(a:range) - 1] + 1
    else
      let start = s:cur_init_pos[0] - 1
      let end   = s:cur_init_pos[0] + 1
    endif
    let range = '\m\%>'. start .'l' . '\%<' . end . 'l'

    return range . group_start . option . a:pattern . group_end
  endif

  if a:command == 'g'
    if len(a:range) > 1
      let start = a:range[len(a:range) - 2]
      let end   = a:range[len(a:range) - 1]
      if end < start
        let temp = start
        let start = end
        let end = temp
      endif
      let start = start - 1
      let end   = end + 1
    elseif len(a:range) == 1
      let start = a:range[len(a:range) - 1] - 1
      let end   = a:range[len(a:range) - 1] + 1
    else
      return option . a:pattern
    endif
    let range = '\m\%>'. start .'l' . '\%<' . end . 'l'
    return range . group_start . option . a:pattern . group_end
  endif

  return ''
endfunction

function! s:position(input) abort
  if type(a:input) == 1 && a:input != ''
    silent! let position = search(a:input, 'c')
    if position != 0
      let s:cur_temp_pos =  [position, 1]
    endif
  elseif type(a:input) == 3 && len(a:input) > 0
    let s:cur_temp_pos =  [a:input[len(a:input) - 1], 1]
  endif

  if g:traces_preserve_view_state
    call cursor(s:cur_init_pos)
  else
    call cursor(s:cur_temp_pos)
  endif
endfunction

function! s:highlight(type, regex, priority) abort
  if &hlsearch && a:regex !=# '' && a:type ==# 'Search'
    let &hlsearch = 0
  endif

  let cur_win = win_getid()
  let prev_win = win_getid(winnr('#'))
  let windows =  win_findbuf(bufnr('%'))
  for window in windows
    noautocmd call win_gotoid(window)
    if !exists('w:traces_highlights')
      let w:traces_highlights = {}
    endif
    if !exists('w:traces_highlights[a:type]')
      let x = {}
      let x.regex = a:regex
      silent! let x.index = matchadd(a:type, a:regex, a:priority)
      let w:traces_highlights[a:type] = x
    elseif w:traces_highlights[a:type].regex !=# a:regex
      if w:traces_highlights[a:type].index !=# -1
        call matchdelete(w:traces_highlights[a:type].index)
      endif
      let w:traces_highlights[a:type].regex = a:regex
      silent! let w:traces_highlights[a:type].index = matchadd(a:type, a:regex, a:priority)
      let s:highlighted = 1
    endif
  endfor
  noautocmd call win_gotoid(prev_win)
  noautocmd call win_gotoid(cur_win)
endfunction

function! s:clean() abort
  if exists('s:cur_init_pos')
    call cursor(s:cur_init_pos)
  endif
  silent! unlet s:show_range
  silent! unlet s:cur_init_pos
  silent! unlet s:cur_temp_pos

  let cur_win = win_getid()
  let prev_win = win_getid(winnr('#'))
  let windows =  win_findbuf(bufnr('%'))
  for window in windows
    noautocmd call win_gotoid(window)
    if exists('w:traces_highlights')
      for key in keys(w:traces_highlights)
        if w:traces_highlights[key].index !=# - 1
          call matchdelete(w:traces_highlights[key].index)
        endif
      endfor
      unlet w:traces_highlights
    endif
  endfor
  noautocmd call win_gotoid(prev_win)
  noautocmd call win_gotoid(cur_win)

  let &hlsearch = s:hlsearch
  silent! unlet s:hlsearch
endfunction

function! s:evaluate_cmdl(cmdl) abort
  let r                 = s:evaluate_range(s:parse_range([], a:cmdl))
  let c                 = {}
  let c.range           = {}
  let c.range.abs       = r.range
  let c.range.pattern   = s:get_selection_regexp(r.range)
  let c.range.specifier = s:get_pattern_regexp('g', len(r.range) > 0 ? [r.range[len(r.range) - 1]] : [], r.pattern)
  let c.cmd             = {}
  let c.cmd.name        = s:get_command(a:cmdl)
  let c.cmd.pattern     = s:get_pattern_regexp(c.cmd.name, r.range, s:get_pattern(c.cmd.name, a:cmdl))
  return c
endfunction

function! s:main(...) abort
  if &buftype ==# 'terminal'
    return
  endif
  let s:highlighted = 0

  " save cursor positions
  if !exists('s:cur_init_pos')
    let s:cur_init_pos = [line('.'), col('.')]
    let s:cur_temp_pos = s:cur_init_pos
  endif
  " restore initial cursor position
  call cursor(s:cur_init_pos)

  let cmdl = s:evaluate_cmdl([s:cmdl])

  " range
  if (cmdl.cmd.name !=# '' || exists('s:show_range')) && !(get(s:, 'keep_pos') && g:traces_whole_file_range == 0)
    call s:highlight('Visual', cmdl.range.pattern, 100)
    call s:highlight('Search', cmdl.range.specifier, 101)
    call s:position(cmdl.range.abs)
  endif

  if cmdl.range.specifier == ''
    call s:highlight('Search', cmdl.cmd.pattern, 101)
    call s:position(cmdl.cmd.pattern)
  endif

  if !has('nvim')
    call winline()
  elseif s:highlighted
    redraw
  endif
endfunction

function! s:track(...) abort
  let current_cmd = getcmdline()
  if s:cmdl !=# current_cmd
    let s:cmdl = current_cmd
    call s:main()
  endif
endfunction

function! s:cmdl_enter() abort
  let s:hlsearch = &hlsearch
  let s:cmdl = getcmdline()
  let s:track_cmd = timer_start(15,function('s:track'),{'repeat':-1})
endfunction

function! s:cmdl_leave() abort
  unlet s:cmdl
  call timer_stop(s:track_cmd)
endfunction

augroup traces_augroup
  autocmd!
  autocmd CmdlineEnter,CmdwinLeave : call s:cmdl_enter()
  autocmd CmdlineLeave,CmdwinEnter : call s:cmdl_leave()
  autocmd CmdlineLeave : call s:clean()
augroup END

let &cpo = s:cpo_save
unlet s:cpo_save
