if !(v:version > 800 || v:version == 800 && has("patch1067") || has('nvim')) || exists("g:loaded_traces_plugin") || &cp
  finish
endif
let g:loaded_traces_plugin = 1

let s:cpo_save = &cpo
set cpo-=C

function! s:trim(...) abort
  if a:0 == 2
    let a:1[0] = strcharpart(a:1[0], a:2)
  else
    let a:1[0] = substitute(a:1[0], '^\s\+', '', '')
  endif
endfunction

function! s:get_range(range, cmd_line) abort
  let specifier = {}
  let specifier.addresses = []

  let while_limit = 0
  let flag = 1
  while flag
    " address part
    call s:trim(a:cmd_line)
    let entry = {}
    " regexp for pattern specifier
    let pattern = '/\%(\\/\|[^/]\)*/\=\|?\%(\\?\|[^?]\)*?\='
    if len(specifier.addresses) == 0
      " \& is not supported
      let address = matchstrpos(a:cmd_line[0],
            \ '\m^\%(\d\+\|\.\|\$\|%\|\*\|''.\|'. pattern . '\|\\/\|\\?\)')
    else
      let address = matchstrpos(a:cmd_line[0],
            \ '\m^\%(' . pattern . '\)' )
    endif
    if address[2] != -1
      call s:trim(a:cmd_line, address[2])
      let entry.address = address[0]
    endif

    " offset
    call s:trim(a:cmd_line)
    let offset = matchstrpos(a:cmd_line[0], '\m^\%(\d\|\s\|+\|-\)\+')
    if offset[2] != -1
      call s:trim(a:cmd_line, offset[2])
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
  call s:trim(a:cmd_line)
  let delimiter = matchstrpos(a:cmd_line[0], '\m^\%(,\|;\)')
  if delimiter[2] != -1
    call s:trim(a:cmd_line, delimiter[2])
    let specifier.delimiter = delimiter[0]
  endif

  " add when addresses or delimiter are found or when one specifier is
  " already known
  if len(specifier.addresses) > 0  || delimiter[2] != -1
        \ || len(a:range) > 0
    call add(a:range, specifier)
  endif

  if delimiter[2] != -1
    return s:get_range(a:range, a:cmd_line)
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

function! s:mark_to_absolute(address, last_position) abort
  let result = {}
  let result.range = []
  let result.valid = 1
  let result.skip  = 0
  let result.regex = ''
  let s:dont_move  = 0

  if has_key(a:address, 'address')

    if     a:address.address =~# '^\d\+'
      let lnum = str2nr(a:address.address)
      call add(result.range, lnum > getpos('$')[1] ? getpos('$')[1] : lnum)

    elseif a:address.address ==  '.'
      call add(result.range, a:last_position)

    elseif a:address.address ==  '$'
      call add(result.range, getpos('$')[1])

    elseif a:address.address ==  '%'
      call add(result.range, 1)
      call add(result.range, getpos('$')[1])
      let s:dont_move = 1

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
      call add(result.range, search(pattern, 'nc'))

    elseif a:address.address =~# '^?.*[^\\]?$\|^??$'
      let pattern = a:address.address
      let pattern = substitute(pattern, '^?', '', '')
      let pattern = substitute(pattern, '?$', '', '')
      let pattern = substitute(pattern, '\\?', '?', '')
      call cursor(a:last_position, 1)
      let s:show_range = 1
      call add(result.range, search(pattern, 'nb'))

    elseif a:address.address =~# '^/.*$'
      let pattern = a:address.address
      let pattern = substitute(pattern, '^/', '', '')
      if len(pattern) == 0
        let pattern = @/
        let result.skip = 1
      endif
      call cursor(a:last_position + 1, 1)
      call add(result.range, search(pattern, 'nc'))
      let s:show_range = 1
      let result.regex = pattern

    elseif a:address.address =~# '^?.*$'
      let pattern = a:address.address
      let pattern = substitute(pattern, '^?', '', '')
      let pattern = substitute(pattern, '\\?', '?', '')
      if len(pattern) == 0
        let pattern = @/
        let result.skip = 1
      endif
      call cursor(a:last_position, 1)
      call add(result.range, search(pattern, 'nb'))
      let s:show_range = 1
      let result.regex = pattern

    elseif a:address.address ==  '\/'
      let pattern = @/
      call cursor(a:last_position + 1, 1)
      call add(result.range, search(pattern, 'nc'))
      let s:show_range = 1

    elseif a:address.address ==  '\?'
      let pattern = @?
      call cursor(a:last_position, 1)
      call add(result.range, search(pattern, 'nb'))
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

  return result
endfunction

function! s:range_to_apsolute(range_structure) abort
  let last_delimiter = ''
  " let range = []
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
            \ use_temp_position ? temp_position : last_position)
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

function! s:get_command(cmd_line) abort
  call s:trim(a:cmd_line)
  let result = matchstrpos(a:cmd_line[0], '\m\w\+!\=')
  if result[2] != -1
    call s:trim(a:cmd_line, result[2])

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
    elseif match(result[0], '\m^\%(d\%[elete]\|j\%[oin]!\=\|<\|le\%[ft]\|>\|y\%[ank]\|co\%[py]\|m\%[ove]\|ce\%[nter]\|ri\%[ght]\|le\%[ft]\|sor\%[t]!\=\|!\|diffg\%[et]\|diffpu\%[t]\|w\%[rite]!\=\|up\%[date]!\=\|wq!\=\|x\%[it]!\=\|exi\%[t]!\=\|cal\%[l]\|foldd\%[oopen]\|folddoc\%[losed]\|lua\|luado\|luafile\|mz\%[scheme]\|mzf\%[ile]\|perld\%[o]\|py\%[thon]\|py\%[thon]\|pydo\|pyf\%[ile]\|rubyd\%[o]\|tc\%[l]\|tcld\%[o]\|r\%[ead]\|ma\%[rk]\|k\|ha\%[rdcopy]!\=\|is\%[earch]!\=\|il\%[ist]!\=\|ij\%[ump]!\=\|isp\%[lit]!\=\|ds\%[earch]!\=\|dli\%[st]!\=\|dj\%[ump]!\=\|dsp\%[lit]!\=\|ter\%[minal]\|p\%[rint]\|l\%[ist]\|nu\%[mber]\|#\|ps\%[earch]!\=\|norm\%[al]!\=\|c\%[hange]!\=\|fo\%[ld]\|foldo\%[pen]!\=\|foldc\%[lose]!\=\|a\%[ppend]!\=\|i\%[nsert]!\=\|=\|z\|z#\)') != -1
      return 'c'
    else
      return ''
    endif
  endif
  return ''
endfunction

function! s:get_pattern(command, cmd_line) abort
  call s:trim(a:cmd_line)
  if get({'s': 1, 'sno': 1, 'sm': 1, 'g': 1}, a:command, 0)
    let delimiter = strcharpart(a:cmd_line[0], 0, 1)
    if delimiter !~ '\W'
      return ''
    endif
    let regexp = '\m^' . delimiter . '\%(\\' . delimiter
          \ . '\|[^' . delimiter . ']\)*' . delimiter . '\='

    try
      let pattern = matchstrpos(a:cmd_line[0], regexp)
    catch
      return ''
    endtry

    if pattern[2] != -1
      call s:trim(a:cmd_line, pattern[2])
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
      let start = s:cursor_initial_pos[0] - 1
      let end   = s:cursor_initial_pos[0] + 1
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

function! s:set_cursor_position(pattern_regex, range, abs_range) abort
  if a:pattern_regex != ''
    let position =  search(a:pattern_regex, 'c')
    if position != 0
      let s:cursor_temp_pos =  position
    endif
  elseif len(a:abs_range) > 0
    call cursor(a:abs_range[len(a:abs_range) - 1], 1)
    let s:cursor_temp_pos =  a:abs_range[len(a:abs_range) - 1]
  endif
  call cursor(s:cursor_temp_pos, 1)
endfunction

function! s:highlight(pattern_regex, selection_regex, last_specifier_pattern, abs_range) abort
  if exists('w:traces_selection_index') && w:traces_selection_index != -1 
    call matchdelete(w:traces_selection_index)
    unlet w:traces_selection_index
  endif

  if exists('w:traces_pattern_index') && w:traces_pattern_index != -1
    call matchdelete(w:traces_pattern_index)
    unlet w:traces_pattern_index
  endif

  try
    let w:traces_selection_index = matchadd('Visual', a:selection_regex, 100)
    if a:last_specifier_pattern != ''
      let w:traces_pattern_index   = matchadd('Search', a:last_specifier_pattern, 101)
    else
      let w:traces_pattern_index   = matchadd('Search', a:pattern_regex, 101)
    endif
    if !get(s:, 'dont_move', 0) || a:pattern_regex != ''
      call s:set_cursor_position(a:pattern_regex, a:selection_regex, a:abs_range)
    endif
    redraw
  catch
  endtry
endfunction


function! s:clean() abort
    if exists('s:old_cmd_line')
      silent! unlet s:old_cmd_line
      silent! unlet s:show_range
      silent! unlet s:cursor_initial_pos
      silent! unlet s:cursor_temp_pos
      silent! unlet s:old_pattern_regex
      silent! unlet s:old_selection_regex
      silent! unlet s:old_last_specifier_pattern
      silent! call  matchdelete(w:traces_selection_index)
      silent! unlet w:traces_selection_index
      silent! call  matchdelete(w:traces_pattern_index)
      silent! unlet w:traces_pattern_index
    endif
endfunction

function! s:main(...) abort
  if getcmdtype() ==# ':' && &buftype != 'terminal'

    " continue only if command line is changed
    let cmd_line = [getcmdline()]
    if get(s:, 'old_cmd_line', '') == cmd_line[0]
      return
    endif
    let s:old_cmd_line = cmd_line[0]

    " save cursor positions
    if !exists('s:cursor_initial_pos')
      let s:cursor_initial_pos = [getpos('.')[1], getpos('.')[2]]
      let s:cursor_temp_pos = s:cursor_initial_pos
    endif

    let range = s:get_range([], cmd_line)
    let selection = s:range_to_apsolute(range)
    let abs_range = selection.range
    let last_specifier_pattern = selection.pattern
    let last_specifier_pattern = s:get_pattern_regexp('g',
          \ len(abs_range) > 0 ? [abs_range[len(abs_range) - 1]] : [], last_specifier_pattern)
    let command = s:get_command(cmd_line)
    let pattern = s:get_pattern(command, cmd_line)

    let pattern_regex =  s:get_pattern_regexp(command, abs_range, pattern)
    let selection_regex =  s:get_selection_regexp(abs_range)

    " redraw only when regular expressions are changed
    if get({'s': 1, 'sno': 1, 'sm': 1, 'g': 1, 'c': 1}, command, 0) || exists('s:show_range')
      if exists('s:old_selection_regex')
        if s:old_selection_regex != selection_regex || s:old_pattern_regex != pattern_regex
              \ || s:old_last_specifier_pattern != last_specifier_pattern
          call s:highlight(pattern_regex, selection_regex, last_specifier_pattern, abs_range)
        endif
      else
        call s:highlight(pattern_regex, selection_regex, last_specifier_pattern, abs_range)
      endif
      let s:old_pattern_regex = pattern_regex
      let s:old_selection_regex = selection_regex
      let s:old_last_specifier_pattern = last_specifier_pattern
    endif

    " restore initial cursor position
    call cursor(s:cursor_initial_pos)
  else
    call s:clean()
  endif
endfunction

augroup traces_cleanup
  autocmd WinLeave * call s:clean()
augroup END

if exists('s:initial_timer')
  call timer_stop(s:initial_timer)
endif
let s:initial_timer = timer_start(15,function('s:main'),{'repeat':-1})

let &cpo = s:cpo_save
unlet s:cpo_save
