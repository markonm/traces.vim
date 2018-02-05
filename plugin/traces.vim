if !exists('##CmdlineEnter') || exists('g:loaded_traces_plugin') || &cp
  finish
endif
let g:loaded_traces_plugin = 1

let s:cpo_save = &cpo
set cpo-=C

let g:traces_preserve_view_state = get(g:, 'traces_preserve_view_state')
let g:traces_substitute_preview  = get(g:, 'traces_substitute_preview', 1)
let s:traces_delay = 0.4

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
    let pattern = '/%(\\.|/@!&.)*/=|\?%(\\.|\?@!&.)*\?='
    if !len(specifier.addresses)
      " \& is not supported
      let address = matchstrpos(a:cmdl[0], '\v^%(\d+|\.|\$|\%|\*|''.|'. pattern . '|\\\/|\\\?)')
    else
      let address = matchstrpos(a:cmdl[0], '\v^%(' . pattern . ')' )
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
  if len(specifier.addresses) || delimiter[2] != -1 || len(a:range)
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

function! s:spec_to_abs(address, last_position, range_size) abort
  let result = {}
  let result.range = []
  let result.valid = 1
  let result.skip  = 0
  let result.regex = ''
  let s:entire_file  = 0

  if has_key(a:address, 'address')

    if     a:address.address =~# '^\d\+'
      let lnum = str2nr(a:address.address)
      call add(result.range, lnum)

    elseif a:address.address ==# '.'
      call add(result.range, a:last_position)

    elseif a:address.address ==# '$'
      call add(result.range, getpos('$')[1])

    elseif a:address.address ==# '%'
      call add(result.range, 1)
      call add(result.range, getpos('$')[1])
      let s:entire_file = 1

    elseif a:address.address ==# '*'
      call add(result.range, getpos('''<')[1])
      call add(result.range, getpos('''>')[1])
      if match(&cpoptions, '\*') != -1
        let result.valid = 0
      endif
      let s:buf[s:nr].show_range = 1

    elseif a:address.address =~# '^''.'
      let mark_position = getpos(a:address.address)
      if mark_position[1]
        call add(result.range, mark_position[1])
      else
        let result.valid = 0
      endif
      let s:buf[s:nr].show_range = 1

    elseif a:address.address =~# '\v^\/%(\\.|.){-}%([^\\]\\)@<!\/$'
      let pattern = a:address.address[1:-2]
      if empty(pattern)
        let pattern = s:last_pattern
      else
        let s:last_pattern = pattern
      endif
      call cursor(a:last_position + 1, 1)
      let s:buf[s:nr].show_range = 1
      silent! let query = search(pattern, 'nc')
      if query == 0
        let result.valid = 0
      endif
      call add(result.range, query)

    elseif a:address.address =~# '\v^\?%(\\.|.){-}%([^\\]\\)@<!\?$'
      let pattern = a:address.address[1:-2]
      let pattern = substitute(pattern, '\\?', '?', '')
      if empty(pattern)
        let pattern = s:last_pattern
      else
        let s:last_pattern = pattern
      endif
      call cursor(a:last_position, 1)
      let s:buf[s:nr].show_range = 1
      silent! let query = search(pattern, 'nb')
      if query == 0
        let result.valid = 0
      endif
      call add(result.range, query)

    elseif a:address.address =~# '^/.*$'
      let pattern = a:address.address[1:]
      call cursor(a:last_position + 1, 1)
      silent! let query = search(pattern, 'nc')

      if !query && !empty(pattern)
        let result.valid = 0
      endif

      " stay at the same position if pattern is not provided
      if !len(pattern)
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
      let pattern = a:address.address[1:]
      let pattern = substitute(pattern, '\\?', '?', '')
      call cursor(a:last_position, 1)
      silent! let query = search(pattern, 'nb')

      if !query && !empty(pattern)
        let result.valid = 0
      endif

      " stay at the same position if pattern is not provided
      if !len(pattern)
        if a:range_size == 0
          let result.skip = 1
        endif
        call add(result.range, a:last_position)
      else
        call add(result.range, query)
      endif

      let s:buf[s:nr].show_range = 1
      let result.regex = pattern

    elseif a:address.address ==# '\/'
      call cursor(a:last_position + 1, 1)
      silent! let query = search(s:last_pattern, 'nc')
      if query == 0
        let result.valid = 0
      endif
      call add(result.range, query)
      let s:buf[s:nr].show_range = 1

    elseif a:address.address ==# '\?'
      call cursor(a:last_position, 1)
      silent! let query = search(s:last_pattern, 'nb')
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
  if len(result.range) && !has_key(a:address, 'address')
    let result.range[0] = result.range[0] + s:offset_to_num(a:address.offset)
  elseif len(result.range) && has_key(a:address, 'offset') &&
     \ a:address.address !~# '%'
    let result.range[0] = result.range[0] + s:offset_to_num(a:address.offset)
  endif

  " treat specifier 0 as 1
  if exists('result.range[0]') && result.range[0] == 0
    let result.range[0] = 1
  endif

  if result.valid && (result.range[0] > getpos('$')[1] || result.range[0] < 0)
    let result.valid = 0
  endif
  return result
endfunction

function! s:evaluate_range(range_structure) abort
  let last_delimiter = ''
  let result = { 'range': []}
  let s:range_valid = 1
  let last_position = getpos('.')[1]
  let last_position = s:buf[s:nr].cur_init_pos[0]
  let result.pattern = ''
  let skip = 0

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
      let query = s:spec_to_abs(address,
            \ use_temp_position ? temp_position : last_position, len(result.range))
      if query.valid
        let temp_position = query.range[-1]
        let use_temp_position = 1
        if !query.skip
          call extend(specifier_result, query.range)
          let result.pattern = query.regex
        endif
        if len(query.range) == 2
          let entire_file = 1
          if len(specifier.addresses) > 1
            let skip = 1
          endif
          break
        endif
      else
        let s:range_valid = 0
      endif
    endfor

    if has_key(specifier, 'delimiter')
      let last_delimiter = specifier.delimiter
    endif

    if len(specifier_result)
      if entire_file
        call extend(result.range, specifier_result)
      elseif len(specifier_result)
        call add(result.range, specifier_result[-1])
      endif
      if last_delimiter ==# ';'
        let last_position = result.range[-1]
      endif
    endif
    if skip
      break
    endif
  endfor

  return s:range_valid ? result : { 'range' : [], 'pattern' : '' }
endfunction

function! s:get_selection_regexp(range) abort
  if empty(a:range) || a:range[-1] > line('$') || !s:range_valid
    return ''
  endif
  if len(a:range) == 1
    let pattern = '\%' . a:range[0] . 'l'
  else
    let start = a:range[-2]
    let end = a:range[-1]
    if end < start
      let temp = start
      let start = end
      let end = temp
    endif
    let start -= 1
    let end += 1
    let pattern = '\%>' . start . 'l\%<' . end . 'l'
  endif
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

function! s:add_flags(pattern, cmdl, type) abort
  if !len(a:pattern)
    return ''
  endif
  if !s:range_valid
    return ''
  endif
  if !len(substitute(a:pattern, '\\[cCvVmM]', '', 'g'))
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
    let start = s:buf[s:nr].cur_init_pos[0] - 1
    let end   = s:buf[s:nr].cur_init_pos[0] + 1
  endif

  " range pattern specifer
  if a:type == 3
    let start = a:cmdl.range.abs[-1] - 1
    let end   = a:cmdl.range.abs[-1] + 1
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

  return range . group_start . option . a:pattern . group_end
endfunction

function! s:parse_global(cmdl) abort
  call s:trim(a:cmdl.string)
  let pattern = '\v^([[:graph:]]&[^[:alnum:]\\"|])(%(\\.|.){-})%((\1)|$)'
  let args = {}
  let r = matchlist(a:cmdl.string[0], pattern)
  if len(r)
    let args.delimiter = r[1]
    let args.pattern   = s:add_flags((empty(r[2]) && !empty(r[3])) ? s:last_pattern : r[2], a:cmdl, 1)
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
    let args.pattern          = s:add_flags((empty(r[2]) && !empty(r[3])) ? s:last_pattern : r[2], a:cmdl, 2)
    let args.string           = r[4]
    let args.last_delimiter   = r[5]
    let args.flags            = r[6]
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

function! s:pos_pattern(pattern, range, delimiter) abort
  if g:traces_preserve_view_state || empty(a:pattern)
    return
  endif
  if len(a:range) > 1 && !get(s:, 'entire_file')
    if a:delimiter ==# '?'
      call cursor([a:range[-1], 1])
      call cursor([a:range[-1], col('$')])
    else
      call cursor([a:range[-2], 1])
    endif
  else
    call cursor(s:buf[s:nr].cur_init_pos)
  endif
  silent! let position = search(a:pattern, 'c')
  if position !=# 0
    let s:moved = 1
  endif
endfunction

function! s:pos_range(range, pattern) abort
  if g:traces_preserve_view_state || empty(a:range)
    return
  endif
  call cursor([a:range[-1], 1])
  if !empty(a:pattern)
    call search(a:pattern, 'c')
  endif
  let s:moved = 1
endfunction

function! s:highlight(group, pattern, priority) abort
  let cur_win = win_getid()
  if exists('s:win[cur_win].hlight[a:group].pattern') && s:win[cur_win].hlight[a:group].pattern ==# a:pattern
    return
  endif
  if !exists('s:win[cur_win].hlight[a:group].pattern') && empty(a:pattern)
    return
  endif

  if &hlsearch && !empty(a:pattern) && a:group ==# 'Search'
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
      let s:highlighted = 1
    elseif s:win[id].hlight[a:group].pattern !=# a:pattern
      if s:win[id].hlight[a:group].index !=# -1
        call matchdelete(s:win[id].hlight[a:group].index)
      endif
      let s:win[id].hlight[a:group].pattern = a:pattern
      silent! let s:win[id].hlight[a:group].index = matchadd(a:group, a:pattern, a:priority)
      let s:highlighted = 1
    endif
    if (&conceallevel !=# 2 || &concealcursor !=# 'c') && a:group ==# 'Conceal'
      let s:win[id].options = get(s:win[id], 'options', {})
      let s:win[id].options.conceallevel = &conceallevel
      let s:win[id].options.concealcursor = &concealcursor
      set conceallevel=2
      set concealcursor=c
    endif
    " highglighting doesn't work properly when cursorline or cursorcolumn is
    " enabled
    if &cursorcolumn || &cursorline
      let s:win[id].options = get(s:win[id], 'options', {})
      let s:win[id].options.cursorcolumn = &cursorcolumn
      let s:win[id].options.cursorline = &cursorline
      set nocursorcolumn
      set nocursorline
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
  if a:cmdl.cmd.args.string =~# '^\\='
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
    call s:pos_pattern(a:cmdl.cmd.args.pattern, a:cmdl.range.abs, a:cmdl.cmd.args.delimiter)
    if (!empty(a:cmdl.cmd.args.string) || !empty(a:cmdl.cmd.args.last_delimiter))
       \  && g:traces_substitute_preview  && !&readonly
      call s:highlight('Search', s:str_start . '\_.\{-}' . s:str_end, 101)
    else
      call s:highlight('Search', a:cmdl.cmd.args.pattern, 101)
    endif

    if g:traces_substitute_preview && !&readonly
      let c = 'noautocmd keepjumps keeppatterns ' . s:format_command(a:cmdl)

      if !exists('s:buf[s:nr].changed')
        let s:buf[s:nr].changed = 0
        let s:buf[s:nr].undo_file = tempname()
        if bufname('%') !=# '[Command Line]'
          noautocmd silent execute 'wundo ' . s:buf[s:nr].undo_file
        endif
      endif

      let tick = b:changedtick
      if !empty(a:cmdl.cmd.args.string) || !empty(a:cmdl.cmd.args.last_delimiter)
        call s:highlight('Conceal', s:str_start . '\|' . s:str_end, 102)
        let lines = line('$')
        let view = winsaveview()
        let ul = &undolevels
        let &undolevels = 0
        silent! execute c
        let &undolevels = ul
        call winrestview(view)
        let s:highlighted = 1
        let lines = lines - line('$')
        if lines && !get(s:, 'entire_file') && !empty(a:cmdl.range.abs)
          if len(a:cmdl.range.abs) == 1
            call add(a:cmdl.range.abs, a:cmdl.range.abs[0])
          endif
          let a:cmdl.range.abs[-1] -= lines
          call s:highlight('Visual', s:get_selection_regexp(a:cmdl.range.abs), 100)
        endif
      endif
      if tick != b:changedtick
        let s:buf[s:nr].changed = 1
      endif
    endif
  endif
endfunction

function! s:live_global(cmdl) abort
  if empty(a:cmdl.range.specifier) && has_key(a:cmdl.cmd.args, 'pattern')
    call s:highlight('Search', a:cmdl.cmd.args.pattern, 101)
    call s:pos_pattern(a:cmdl.cmd.args.pattern, a:cmdl.range.abs, a:cmdl.cmd.args.delimiter)
  endif
endfunction

function! s:cmdl_enter() abort
  let s:buf[s:nr] = {}
  let s:buf[s:nr].view = winsaveview()
  let s:buf[s:nr].show_range = 0
  let s:buf[s:nr].duration = 0
  let s:buf[s:nr].hlsearch = &hlsearch
  let s:buf[s:nr].cword = expand('<cword>')
  let s:buf[s:nr].cWORD = expand('<cWORD>')
  let s:buf[s:nr].cfile = expand('<cfile>')
  let s:buf[s:nr].cur_init_pos = [line('.'), col('.')]
  call s:save_marks()
endfunction

function! s:cmdl_leave() abort
  let s:nr = bufnr('%')
  if !exists('s:buf[s:nr]')
    return
  endif
  " changes
  if exists('s:buf[s:nr].changed')
    if s:buf[s:nr].changed
      noautocmd keepjumps silent undo
      call s:restore_marks()
    endif
    if bufname('%') !=# '[Command Line]'
      silent! execute 'noautocmd rundo ' . s:buf[s:nr].undo_file
    endif
  endif

  " highlights
  if exists('s:win[win_getid()]')
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
            execute 'let &' . option . '="' . s:win[id].options[option] . '"'
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
  endif

  if &hlsearch !=# s:buf[s:nr].hlsearch
    let &hlsearch = s:buf[s:nr].hlsearch
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
  let cmdl.range.pattern   = s:get_selection_regexp(r.range)
  let cmdl.range.specifier = s:add_flags(r.pattern, cmdl, 3)

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

function! s:init(...) abort
  if &buftype ==# 'terminal' || (has('nvim') && !empty(&inccommand))
    if exists('s:track_cmdl_timer')
      call timer_stop(s:track_cmdl_timer)
    endif
    return
  endif

  let s:nr =  bufnr('%')
  if !exists('s:buf[s:nr]')
    call s:cmdl_enter()
  endif

  let s:highlighted = 0
  let s:moved       = 0
  let s:last_pattern = @/

  if s:buf[s:nr].duration < s:traces_delay
    let start_time = reltime()
  endif

  if exists('s:buf[s:nr].changed') && s:buf[s:nr].changed
    let view = winsaveview()
    noautocmd keepjumps silent undo
    let s:buf[s:nr].changed = 0
    let s:highlighted = 1
    call s:restore_marks()
    call winrestview(view)
  endif
  let cmdl = s:evaluate_cmdl([s:cmdl])

  if s:buf[s:nr].duration < s:traces_delay
    " range preview
    if (!empty(cmdl.cmd.name) || s:buf[s:nr].show_range) && !get(s:, 'entire_file')
      call s:highlight('Visual', cmdl.range.pattern, 100)
      if empty(cmdl.cmd.name)
        call s:highlight('Search', cmdl.range.specifier, 101)
      endif
      call s:pos_range(cmdl.range.abs, cmdl.range.specifier)
    endif

    " cmd preview
    if cmdl.cmd.name =~# '\v^%(s%[ubstitute]|sm%[agic]|sno%[magic])$'
      call s:live_substitute(cmdl)
    endif
    if cmdl.cmd.name =~# '\v^%(g%[lobal]\!=|v%[global])$'
      call s:live_global(cmdl)
    endif

    " clear unnecessary hl
    if empty(cmdl.range.pattern) || get(s:, 'entire_file')
      call s:highlight('Visual', '', 100)
    endif
    if empty(cmdl.cmd.name) && empty(cmdl.range.specifier)
      call s:highlight('Search', '', 101)
    endif
  endif

  " move to starting position if necessary
  if !s:moved && winsaveview() != s:buf[s:nr].view && !wildmenumode()
    call winrestview(s:buf[s:nr].view)
  endif

  " update screen if necessary
  if s:highlighted
    if has('nvim')
      redraw
    else
      call winline()
      " after patch 8.0.1449, necessary for linux cui, otherwise highlighting
      " is not drawn properly
      silent! call feedkeys("\<left>\<right>", 'tn')
    endif
  endif

  if exists('start_time')
    let s:buf[s:nr].duration = reltimefloat(reltime(start_time))
  endif
endfunction

function! s:track_cmdl(...) abort
  let current_cmd = getcmdline()
  if get(s:, 'cmdl', '') !=# current_cmd
    let s:cmdl = current_cmd
    call s:init()
  endif
endfunction

function! s:cmdline_changed() abort
  if exists('s:start_init_timer')
    call timer_stop(s:start_init_timer)
    unlet s:start_init_timer
  endif
  let s:cmdl = getcmdline()
  let s:start_init_timer = timer_start(1,function('s:init'))
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
  if exists('##CmdlineChanged')
    let s:track_cmdl_timer = timer_start(30,function('s:create_cmdl_changed_au'))
  else
    let s:track_cmdl_timer = timer_start(30,function('s:track_cmdl'),{'repeat':-1})
  endif
endfunction

function! s:t_stop() abort
  if exists('s:cmdl')
    unlet s:cmdl
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

function! s:get_cword() abort
  return s:buf[s:nr].cword
endfunction

function! s:get_cWORD() abort
  return s:buf[s:nr].cWORD
endfunction

function! s:get_cfile() abort
  return s:buf[s:nr].cfile
endfunction

function! s:get_pfile() abort
  let result = split(globpath(&path, s:buf[s:nr].cfile), '\n')
  if len(result) && len(s:buf[s:nr].cfile)
    return result[-1]
  endif
  return ''
endfunction

function! s:check_b() abort
  let s:nr =  bufnr('%')
  if getcmdtype() == ':' && exists('s:buf[s:nr]')
    return 1
  endif
endfunction

silent! cnoremap <unique> <expr> <c-r><c-w> <sid>check_b() ? <sid>get_cword() : "\<c-r>\<c-w>"
silent! cnoremap <unique> <expr> <c-r><c-a> <sid>check_b() ? <sid>get_cWORD() : "\<c-r>\<c-a>"
silent! cnoremap <unique> <expr> <c-r><c-f> <sid>check_b() ? <sid>get_cfile() : "\<c-r>\<c-f>"
silent! cnoremap <unique> <expr> <c-r><c-p> <sid>check_b() ? <sid>get_pfile() : "\<c-r>\<c-p>"

silent! cnoremap <unique> <expr> <c-r><c-r><c-w> <sid>check_b() ? "\<c-r>\<c-r>=\<sid>get_cword()\<cr>" : "\<c-r>\<c-r>\<c-w>"
silent! cnoremap <unique> <expr> <c-r><c-r><c-a> <sid>check_b() ? "\<c-r>\<c-r>=\<sid>get_cWORD()\<cr>" : "\<c-r>\<c-r>\<c-a>"
silent! cnoremap <unique> <expr> <c-r><c-r><c-f> <sid>check_b() ? "\<c-r>\<c-r>=\<sid>get_cfile()\<cr>" : "\<c-r>\<c-r>\<c-f>"
silent! cnoremap <unique> <expr> <c-r><c-r><c-p> <sid>check_b() ? "\<c-r>\<c-r>=\<sid>get_pfile()\<cr>" : "\<c-r>\<c-r>\<c-p>"

silent! cnoremap <unique> <expr> <c-r><c-o><c-w> <sid>check_b() ? "\<c-r>\<c-r>=\<sid>get_cword()\<cr>" : "\<c-r>\<c-o>\<c-w>"
silent! cnoremap <unique> <expr> <c-r><c-o><c-a> <sid>check_b() ? "\<c-r>\<c-r>=\<sid>get_cWORD()\<cr>" : "\<c-r>\<c-o>\<c-a>"
silent! cnoremap <unique> <expr> <c-r><c-o><c-f> <sid>check_b() ? "\<c-r>\<c-r>=\<sid>get_cfile()\<cr>" : "\<c-r>\<c-o>\<c-f>"
silent! cnoremap <unique> <expr> <c-r><c-o><c-p> <sid>check_b() ? "\<c-r>\<c-r>=\<sid>get_pfile()\<cr>" : "\<c-r>\<c-o>\<c-p>"

augroup traces_augroup
  autocmd!
  autocmd CmdlineEnter,CmdwinLeave : call s:t_start()
  autocmd CmdlineLeave,CmdwinEnter : call s:t_stop()
  autocmd CmdlineLeave : call s:cmdl_leave()
augroup END

let &cpo = s:cpo_save
unlet s:cpo_save
