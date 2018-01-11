if !exists('##CmdlineEnter') || exists("g:loaded_traces_plugin") || &cp
  finish
endif
let g:loaded_traces_plugin = 1

let s:cpo_save = &cpo
set cpo-=C

let g:traces_whole_file_range    = get(g:, 'traces_whole_file_range')
let g:traces_preserve_view_state = get(g:, 'traces_preserve_view_state')
let g:traces_substitute_preview  = get(g:, 'traces_substitute_preview', 1)

let s:cmd_pattern = '\v\C^%('
                \ . '\!|'
                \ . '\#|'
                \ . '\<|'
                \ . '\=|'
                \ . '\>|'
                \ . 'a%[ppend]\w@!\!=|'
                \ . 'c%[hange]\w@!\!=|'
                \ . 'cal%[l]\w@!|'
                \ . 'ce%[nter]\w@!|'
                \ . 'co%[py]\w@!|'
                \ . 'd%[elete]\w@!|'
                \ . 'diffg%[et]\w@!|'
                \ . 'diffpu%[t]\w@!|'
                \ . 'dj%[ump]\w@!\!=|'
                \ . 'dli%[st]\w@!\!=|'
                \ . 'ds%[earch]\w@!\!=|'
                \ . 'dsp%[lit]\w@!\!=|'
                \ . 'exi%[t]\w@!\!=|'
                \ . 'fo%[ld]\w@!|'
                \ . 'foldc%[lose]\w@!\!=|'
                \ . 'foldd%[oopen]\w@!|'
                \ . 'folddoc%[losed]\w@!|'
                \ . 'foldo%[pen]\w@!\!=|'
                \ . 'g%[lobal]\w@!\!=|'
                \ . 'ha%[rdcopy]\w@!\!=|'
                \ . 'i%[nsert]\w@!\!=|'
                \ . 'ij%[ump]\w@!\!=|'
                \ . 'il%[ist]\w@!\!=|'
                \ . 'is%[earch]\w@!\!=|'
                \ . 'isp%[lit]\w@!\!=|'
                \ . 'j%[oin]\w@!\!=|'
                \ . 'k\w@!|'
                \ . 'l%[ist]\w@!|'
                \ . 'le%[ft]\w@!|'
                \ . 'le%[ft]\w@!|'
                \ . 'luado\w@!|'
                \ . 'luafile\w@!|'
                \ . 'lua\w@!|'
                \ . 'm%[ove]\w@!|'
                \ . 'ma%[rk]\w@!|'
                \ . 'mz%[scheme]\w@!|'
                \ . 'mzf%[ile]\w@!|'
                \ . 'norm%[al]\w@!\!=|'
                \ . 'nu%[mber]\w@!|'
                \ . 'p%[rint]\w@!|'
                \ . 'perld%[o]\w@!|'
                \ . 'ps%[earch]\w@!\!=|'
                \ . 'py%[thon]\w@!|'
                \ . 'py%[thon]\w@!|'
                \ . 'pydo\w@!|'
                \ . 'pyf%[ile]\w@!|'
                \ . 'r%[ead]\w@!|'
                \ . 'ri%[ght]\w@!|'
                \ . 'rubyd%[o]\w@!|'
                \ . 's%[ubstitute]\w@!|'
                \ . 'sm%[agic]\w@!|'
                \ . 'sno%[magic]\w@!|'
                \ . 'sor%[t]\w@!\!=|'
                \ . 'tc%[l]\w@!|'
                \ . 'tcld%[o]\w@!|'
                \ . 'ter%[minal]\w@!|'
                \ . 't\w@!|'
                \ . 'up%[date]\w@!\!=|'
                \ . 'v%[global]\w@!|'
                \ . 'w%[rite]\w@!\!=|'
                \ . 'wq\w@!\!=|'
                \ . 'x%[it]\w@!\!=|'
                \ . 'y%[ank]\w@!|'
                \ . 'z\#|'
                \ . 'z\w@!'
                \ . ')'

let s:str_start = ''
let s:str_end   = ''

let s:win = {}
let s:buf = {}

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
      let s:buf[s:nr].show_range = 1

    elseif a:address.address =~# '^''.'
      let mark_position = getpos(a:address.address)
      if !mark_position[0]
        call add(result.range, mark_position[1])
      else
        let result.valid = 0
      endif
      let s:buf[s:nr].show_range = 1

    elseif a:address.address =~# '^/.*[^\\]/$\|^//$'
      let pattern = a:address.address
      let pattern = substitute(pattern, '^/', '', '')
      let pattern = substitute(pattern, '/$', '', '')
      call cursor(a:last_position + 1, 1)
      let s:buf[s:nr].show_range = 1
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
      let s:buf[s:nr].show_range = 1
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

      let s:buf[s:nr].show_range = 1
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

      let s:buf[s:nr].show_range = 1
      let result.regex = pattern

    elseif a:address.address ==  '\/'
      let pattern = @/
      call cursor(a:last_position + 1, 1)
      silent! let query = search(pattern, 'nc')
      if query == 0
        let result.valid = 0
      endif
      call add(result.range, query)
      let s:buf[s:nr].show_range = 1

    elseif a:address.address ==  '\?'
      let pattern = @?
      call cursor(a:last_position, 1)
      silent! let query = search(pattern, 'nb')
      if query == 0
        let result.valid = 0
      endif
      call add(result.range, query)
      let s:buf[s:nr].show_range = 1
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
  let result = matchstrpos(a:cmdl[0], s:cmd_pattern)
  if result[2] != -1
    call s:trim(a:cmdl, result[2])
    return result[0]
  endif
  return ''
endfunction

function! s:add_flags(pattern, cmdl, type) abort
  if !len(a:pattern)
    return ''
  endif
  if !len(substitute(a:pattern, '\\[cCvVmM]', '', 'g'))
    return ''
  endif

  let option = ''
  let group_start = '\%('
  let group_end   = '\m\)'

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

  if len(a:cmdl.range.abs) > 1
    let start = a:cmdl.range.abs[-2]
    let end   = a:cmdl.range.abs[-1]
    if end < start
      let temp = start
      let start = end
      let end = temp
    endif
    let start = start - 1
    let end   = end + 1
  elseif len(a:cmdl.range.abs) == 1
    let start = a:cmdl.range.abs[-1] - 1
    let end   = a:cmdl.range.abs[-1] + 1
  elseif a:type ==# 1
    return option . a:pattern
  elseif a:type ==# 2
    let start = s:win[s:win_id].cur_init_pos[0] - 1
    let end   = s:win[s:win_id].cur_init_pos[0] + 1
  endif

  " range pattern specifer
  if a:type == 3
    let start = a:cmdl.range.abs[-1] - 1
    let end   = a:cmdl.range.abs[-1] + 1
  endif

  let range = '\m\%>'. start .'l' . '\%<' . end . 'l'
  return range . group_start . option . a:pattern . group_end
endfunction

function! s:parse_global(cmdl) abort
  call s:trim(a:cmdl.string)
  let pattern = '\v^([[:graph:]]&[^[:alnum:]\\"|])(%(\\.|.){-})%(\1|$)'
  let args = {}
  let r = matchlist(a:cmdl.string[0], pattern)
  if len(r)
    let args.pattern = s:add_flags(r[2], a:cmdl, 1)
  endif
  return args
endfunction

function! s:parse_substitute(cmdl) abort
  call s:trim(a:cmdl.string)
  let pattern = '\v^([[:graph:]]&[^[:alnum:]\\"|])(%(\\\1|\1@!&.)*)%(\1%((%(\\\1|\1@!&.)*)%(\1([&cegiInp#lr]+)=)=)=)=$'
  let args = {}
  let r = matchlist(a:cmdl.string[0], pattern)
  if len(r)
    let args.delimiter   = r[1]
    let args.pattern_org = r[2]
    let args.pattern     = s:add_flags(r[2], a:cmdl, 2)
    let args.string      = r[3]
    let args.flags       = r[4]
  endif
  return args
endfunction

function! s:parse_command(cmdl) abort
  let a:cmdl.cmd.name = s:get_command(a:cmdl.string)
  if a:cmdl.cmd.name =~# '\v^%(g%[lobal]\!=|v%[global])$'
    let a:cmdl.cmd.args = s:parse_global(a:cmdl)
  elseif a:cmdl.cmd.name =~# '\v^%(s%[ubstitute]|sm%[agic]|sno%[magic])$'
    let a:cmdl.cmd.args = s:parse_substitute(a:cmdl)
  endif
endfunction

function! s:position(input) abort
  if type(a:input) == 1 && a:input != ''
    silent! let position = search(a:input, 'c')
    if position != 0
      let s:win[s:win_id].cur_temp_pos =  [position, 1]
    endif
  elseif type(a:input) == 3 && len(a:input) > 0
    let s:win[s:win_id].cur_temp_pos =  [a:input[len(a:input) - 1], 1]
  endif

  if g:traces_preserve_view_state
    call cursor(s:win[s:win_id].cur_init_pos)
  else
    call cursor(s:win[s:win_id].cur_temp_pos)
  endif
endfunction

function! s:highlight(group, pattern, priority) abort
  let cur_win = win_getid()
  if exists('s:win[cur_win].hlight[a:group].pattern') && s:win[cur_win].hlight[a:group].pattern ==# a:pattern
    return
  endif

  if &hlsearch && a:pattern !=# '' && a:group ==# 'Search'
    let &hlsearch = 0
  endif
  if &scrolloff !=# 0
    let scrolloff = &scrolloff
    let &scrolloff = 0
  endif

  let alt_win = win_getid(winnr('#'))
  let windows = filter(win_findbuf(s:nr), {_, val -> win_id2win(val)})
  for id in windows
    noautocmd call win_gotoid(id)
    let s:win[id] = get(s:win, id, {})
    let s:win[id].hlight = get(s:win[id], 'hlight', {})

    if !exists('s:win[id].hlight[a:group]')
      let x = {}
      let x.pattern = a:pattern
      silent! let x.index = matchadd(a:group, a:pattern, a:priority)
      let s:win[id].hlight[a:group] = x
    elseif s:win[id].hlight[a:group].pattern !=# a:pattern
      if s:win[id].hlight[a:group].index !=# -1
        call matchdelete(s:win[id].hlight[a:group].index)
      endif
      let s:win[id].hlight[a:group].pattern = a:pattern
      silent! let s:win[id].hlight[a:group].index = matchadd(a:group, a:pattern, a:priority)
      let s:highlighted = 1
    endif
    if &conceallevel !=# 2 || &concealcursor !=# 'c'
      let s:win[id].options = {}
      let s:win[id].options.conceallevel = &conceallevel
      let s:win[id].options.concealcursor = &concealcursor
      set conceallevel=2
      set concealcursor=c
    endif
  endfor
  if bufname('%') !=# '[Command Line]'
    noautocmd call win_gotoid(alt_win)
    noautocmd call win_gotoid(cur_win)
  endif
  if exists('scrolloff')
    let &scrolloff = scrolloff
  endif
endfunction

function! s:format_command(cmdl) abort
  let c = ''
  if len(a:cmdl.range.abs) == 0
    let c .= s:win[s:win_id].cur_init_pos[0]
  elseif len(a:cmdl.range.abs) == 1
    let c .= a:cmdl.range.abs[0]
  else
    let c .= a:cmdl.range.abs[-2]
    let c .= ';'
    let c .= a:cmdl.range.abs[-1]
  endif
  let c .= 's'
  let c .= a:cmdl.cmd.args.delimiter
  let c .= a:cmdl.cmd.args.pattern_org
  let c .= a:cmdl.cmd.args.delimiter
  if a:cmdl.cmd.args.string =~ '^\\='
    let c .= '\=' . "'" . s:str_start . "'" . '
          \ . (' . substitute(a:cmdl.cmd.args.string, '^\\=', '', '') . ')
          \ . ' . "'" . s:str_end . "'"
  else
    let c .= s:str_start . a:cmdl.cmd.args.string . s:str_end
  endif
  let c .= a:cmdl.cmd.args.delimiter
  let c .= substitute(a:cmdl.cmd.args.flags, '[^giI]', '', 'g')
  return c
endfunction

function! s:live_substitute(cmdl) abort
  if has_key(a:cmdl.cmd.args, 'string')
    call s:position(a:cmdl.cmd.args.pattern)
    if a:cmdl.cmd.args.string != '' && g:traces_substitute_preview && !has('nvim')
      call s:highlight('Search', s:str_start . '.\{-}' . s:str_end, 101)
      call s:highlight('Conceal', s:str_start . '\|' . s:str_end, 102)
    else
      call s:highlight('Search', a:cmdl.cmd.args.pattern, 101)
    endif

    if g:traces_substitute_preview && !has('nvim')
      let c = 'noautocmd keepjumps keeppatterns ' . s:format_command(a:cmdl)

      if !exists('s:buf[s:nr].changed')
        let s:buf[s:nr].changed = 0
        let s:buf[s:nr].undo_file = tempname()
        if bufname('%') !=# '[Command Line]'
          noautocmd silent execute 'wundo ' . s:buf[s:nr].undo_file
        endif
      endif

      let tick = b:changedtick
      if a:cmdl.cmd.args.string != ''
        let view = winsaveview()
        let ul = &undolevels
        let &undolevels = 0
        silent! execute c
        let &undolevels = ul
        call winrestview(view)
      endif
      if tick != b:changedtick
        let s:buf[s:nr].changed = 1
      endif
    endif
  endif
endfunction

function! s:live_global(cmdl) abort
  if a:cmdl.range.specifier == '' && has_key(a:cmdl.cmd.args, 'pattern')
    call s:highlight('Search', a:cmdl.cmd.args.pattern, 101)
    call s:position(a:cmdl.cmd.args.pattern)
  endif
endfunction

function! s:cmdl_enter() abort
  let s:nr =  bufnr('%')
  let s:buf[s:nr] = {}
  let s:buf[s:nr].view = winsaveview()
  let s:buf[s:nr].show_range = 0
  let s:buf[s:nr].duration = 0
  let s:buf[s:nr].hlsearch = &hlsearch
endfunction

function! s:cmdl_leave() abort
  let s:nr = bufnr('%')
  " changes
  if exists('s:buf[s:nr].changed')
    if s:buf[s:nr].changed
      noautocmd keepjumps silent undo
    endif
    if bufname('%') !=# '[Command Line]'
      try
        silent execute 'noautocmd rundo ' . s:buf[s:nr].undo_file
      catch
      endtry
    endif
  endif


  " highlights
  if &scrolloff !=# 0
    let scrolloff = &scrolloff
    let &scrolloff = 0
  endif
  let cur_win = win_getid()
  let alt_win = win_getid(winnr('#'))
  let windows = filter(win_findbuf(s:nr), {_, val -> win_id2win(val)})
  for id in windows
    noautocmd call win_gotoid(id)
    if exists('s:win[id]')
      if exists('s:win[id].hlight')
        for group in keys(s:win[id].hlight)
          if s:win[id].hlight[group].index !=# - 1
            call matchdelete(s:win[id].hlight[group].index)
          endif
        endfor
      endif
      if exists('s:win[id].options')
        for option in keys(s:win[id].options)
          execute 'set ' . option . '=' . s:win[id].options[option]
        endfor
      endif
      unlet s:win[id]
    endif
  endfor
  if bufname('%') !=# '[Command Line]'
    noautocmd call win_gotoid(alt_win)
    noautocmd call win_gotoid(cur_win)
  endif
  if exists('scrolloff')
    let &scrolloff = scrolloff
  endif

  let &hlsearch = s:buf[s:nr].hlsearch
  call winrestview(s:buf[s:nr].view)
  unlet s:buf[s:nr]
endfunction

function! s:evaluate_cmdl(string) abort
  let cmdl                 = {}
  let cmdl.string          = a:string
  let r                    = s:evaluate_range(s:parse_range([], cmdl.string))
  let cmdl.range           = {}
  let cmdl.range.abs       = r.range
  let cmdl.range.pattern   = s:get_selection_regexp(r.range)
  let cmdl.range.specifier = s:add_flags(r.pattern, cmdl, 3)

  let cmdl.cmd             = {}
  let cmdl.cmd.args        = {}
  call s:parse_command(cmdl)

  return cmdl
endfunction

function! s:save_marks() abort
  let s:buf[s:nr] = get(s:buf, s:nr, {})
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

function! s:init(...) abort
  let s:nr =  bufnr('%')
  if &buftype ==# 'terminal'
    return
  endif
  call s:save_marks()
  let s:highlighted = 0

  let s:win_id = win_getid()
  let s:win[s:win_id] = get(s:win, s:win_id, {})

  " save cursor positions
  if !exists('s:win[s:win_id].cur_init_pos')
    let s:win[s:win_id].cur_init_pos = [line('.'), col('.')]
    let s:win[s:win_id].cur_temp_pos = [line('.'), col('.')]
  endif

  if exists('s:buf[s:nr].changed') && s:buf[s:nr].changed
    noautocmd keepjumps silent undo
    let s:buf[s:nr].changed = 0
  endif
  call s:restore_marks()

  " restore initial cursor position
  call cursor(s:win[s:win_id].cur_init_pos)

  let cmdl = s:evaluate_cmdl([s:cmdl])

  " range
  if (cmdl.cmd.name !=# '' || s:buf[s:nr].show_range) &&
        \ !(get(s:, 'keep_pos') && g:traces_whole_file_range == 0)
    call s:highlight('Visual', cmdl.range.pattern, 100)
    if cmdl.cmd.name ==# ''
      call s:highlight('Search', cmdl.range.specifier, 101)
    endif
    call s:position(cmdl.range.abs)
  endif

  if s:buf[s:nr].duration < 0.2
    let start_time = reltime()
    if cmdl.cmd.name =~# '\v^%(s%[ubstitute]|sm%[agic]|sno%[magic])$'
      call s:live_substitute(cmdl)
    endif
    if cmdl.cmd.name =~# '\v^%(g%[lobal]\!=|v%[global])$'
      call s:live_global(cmdl)
    endif
    let s:buf[s:nr].duration = reltimefloat(reltime(start_time))
  endif

  if !has('nvim')
    call winline()
  elseif s:highlighted
    redraw
  endif
endfunction

function! s:track_cmdl(...) abort
  let current_cmd = getcmdline()
  if s:cmdl !=# current_cmd
    let s:cmdl = current_cmd
    call s:init()
  endif
endfunction

function! s:t_start() abort
  let s:cmdl = getcmdline()
  let s:track_cmdl_timer = timer_start(15,function('s:track_cmdl'),{'repeat':-1})
endfunction

function! s:t_stop() abort
  unlet s:cmdl
  call timer_stop(s:track_cmdl_timer)
endfunction

augroup traces_augroup
  autocmd!
  autocmd CmdlineEnter,CmdwinLeave : call s:t_start()
  autocmd CmdlineLeave,CmdwinEnter : call s:t_stop()
  autocmd CmdlineEnter : call s:cmdl_enter()
  autocmd CmdlineLeave : call s:cmdl_leave()
augroup END

let &cpo = s:cpo_save
unlet s:cpo_save
