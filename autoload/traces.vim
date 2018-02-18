let s:cpo_save = &cpo
set cpo-=C

let s:timeout = 400
let s:s_timeout = 300

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

let s:s_start = ''
let s:s_end   = ''

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
      " if offset is present but specifier is missing add '.' specifier
      if !has_key(entry, 'address')
        let entry.address = '.'
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
      call add(specifier.addresses, { 'address': '.' })
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

function! s:spec_to_abs(address, last_position, range_size) abort
  let result = {}
  let result.range = []
  let result.valid = 1
  let result.regex = ''
  let s:entire_file  = 0

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
    call cursor(a:last_position, 1)
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
    silent! let query = search(pattern, 'nc', 0, s:s_timeout)
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
    silent! let query = search(pattern, 'nb', 0, s:s_timeout)
    if query == 0
      let result.valid = 0
    endif
    call add(result.range, query)

  elseif a:address.address =~# '^/.*$'
    let pattern = a:address.address[1:]
    call cursor(a:last_position + 1, 1)
    silent! let query = search(pattern, 'nc', 0, s:s_timeout)

    if !query && !empty(pattern)
      let result.valid = 0
    endif

    " stay at the same position if pattern is not provided
    if !empty(pattern)
      call add(result.range, query)
    elseif a:range_size
      call add(result.range, a:last_position)
    endif

    let s:buf[s:nr].show_range = 1
    let result.regex = pattern

  elseif a:address.address =~# '^?.*$'
    let pattern = a:address.address[1:]
    let pattern = substitute(pattern, '\\?', '?', '')
    call cursor(a:last_position, 1)
    silent! let query = search(pattern, 'nb', 0, s:s_timeout)

    if !query && !empty(pattern)
      let result.valid = 0
    endif

    " stay at the same position if pattern is not provided
    if !empty(pattern)
      call add(result.range, query)
    elseif a:range_size
      call add(result.range, a:last_position)
    endif

    let s:buf[s:nr].show_range = 1
    let result.regex = pattern

  elseif a:address.address ==# '\/'
    call cursor(a:last_position + 1, 1)
    silent! let query = search(s:last_pattern, 'nc', 0, s:s_timeout)
    if query == 0
      let result.valid = 0
    endif
    call add(result.range, query)
    let s:buf[s:nr].show_range = 1

  elseif a:address.address ==# '\?'
    call cursor(a:last_position, 1)
    silent! let query = search(s:last_pattern, 'nb', 0, s:s_timeout)
    if query == 0
      let result.valid = 0
    endif
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
      let query = s:spec_to_abs(address, tmp_pos, !empty(result.range))
      " % specifier doesn't accept additional addresses
      if !query.valid || len(query.range) == 2 && len(specifier.addresses) > 1
        let s:range_valid = 0
        break
      endif
      " it is empty when we want to skip empty unclosed pattern specifier
      if !empty(query.range)
        let tmp_pos = query.range[-1]
      endif
      let specifier_result = deepcopy(query.range)
      let result.pattern = query.regex
    endfor
    if !s:range_valid
      break
    endif

    call extend(result.range, specifier_result)
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

  if !empty(a:cmdl.range.abs)
    let start = a:cmdl.range.abs[-2] - 1
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

function! s:pos_pattern(pattern, range, delimiter, type) abort
  if g:traces_preserve_view_state || empty(a:pattern)
    return
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
endfunction

function! s:pos_range(end, pattern) abort
  if g:traces_preserve_view_state || empty(a:end)
    return
  endif
  call cursor([a:end, 1])
  if !empty(a:pattern)
    call search(a:pattern, 'c', a:end, s:s_timeout)
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
    " highlighting doesn't work properly when cursorline or cursorcolumn is
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
    let c .= '\=' . "'" . s:s_start . "'" . '
          \ . (' . substitute(a:cmdl.cmd.args.string, '^\\=', '', '') . ')
          \ . ' . "'" . s:s_end . "'"
  else
    " make ending single backslash literal or else it will escape character
    " inside s_end
    if substitute(a:cmdl.cmd.args.string, '\\\\', '', 'g') =~# '\\$'
      let c .= s:s_start . a:cmdl.cmd.args.string . '\' . s:s_end
    else
      let c .= s:s_start . a:cmdl.cmd.args.string . s:s_end
    endif
  endif
  let c .= a:cmdl.cmd.args.delimiter
  let c .= substitute(a:cmdl.cmd.args.flags, '[^giI]', '', 'g')
  return c
endfunction

function! s:live_substitute(cmdl) abort
  if empty(a:cmdl.cmd.args)
    return
  endif

  let ptrn  = a:cmdl.cmd.args.pattern
  let str   = a:cmdl.cmd.args.string
  let range = a:cmdl.range.abs
  let dlm   = a:cmdl.cmd.args.delimiter
  let l_dlm = a:cmdl.cmd.args.last_delimiter

  call s:pos_pattern(ptrn, range, dlm, 1)

  if !g:traces_substitute_preview || &readonly || !&modifiable || empty(str) && empty(l_dlm)
    call s:highlight('Search', ptrn, 101)
    return
  endif

  call s:save_undo_history()

  if s:buf[s:nr].undo_file is 0
    call s:highlight('Search', ptrn, 101)
    return
  endif

  let cmd = 'noautocmd keepjumps keeppatterns ' . s:format_command(a:cmdl)
  let tick = b:changedtick

  let lines = line('$')
  let view = winsaveview()
  let ul = &undolevels
  let &undolevels = 0
  silent! execute cmd
  let &undolevels = ul

  if tick == b:changedtick
    return
  endif

  let s:buf[s:nr].changed = 1

  call winrestview(view)
  let s:highlighted = 1
  let lines = lines - line('$')

  if lines && !get(s:, 'entire_file') && !empty(range)
    if len(range) == 1
      call add(range, range[0])
    endif
    let range[-1] -= lines
    call s:highlight('Visual', s:get_selection_regexp(range), 100)
  endif
  call s:highlight('Search', s:s_start . '\_.\{-}' . s:s_end, 101)
  call s:highlight('Conceal', s:s_start . '\|' . s:s_end, 102)
endfunction

function! s:live_global(cmdl) abort
  if empty(a:cmdl.range.specifier) && has_key(a:cmdl.cmd.args, 'pattern')
    call s:highlight('Search', a:cmdl.cmd.args.pattern, 101)
    call s:pos_pattern(a:cmdl.cmd.args.pattern, a:cmdl.range.abs, a:cmdl.cmd.args.delimiter, 0)
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
  let s:buf[s:nr].seq_last = undotree().seq_last
  let s:buf[s:nr].changed = 0
  let s:buf[s:nr].cmdheight = &cmdheight
  call s:save_marks()
endfunction

function! traces#cmdl_leave() abort
  let s:nr = bufnr('%')
  if !exists('s:buf[s:nr]')
    return
  endif

  call s:restore_undo_history()

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
  if &cmdheight !=# s:buf[s:nr].cmdheight
    let &cmdheight = s:buf[s:nr].cmdheight
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
  let cmdl.range.end       = r.end

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
  if bufname('%') ==# '[Command Line]' || !s:buf[s:nr].seq_last
    let s:buf[s:nr].undo_file = 1
    return
  endif

  let s:buf[s:nr].undo_file = tempname()
  let start_time = reltime()
  noautocmd silent execute 'wundo ' . s:buf[s:nr].undo_file
  if !filereadable(s:buf[s:nr].undo_file)
    let s:buf[s:nr].undo_file = 0
  endif
  if (reltimefloat(reltime(start_time)) * 1000) > s:timeout
    let s:buf[s:nr].undo_file = 0
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
  if has('win32') && !has('nvim')
    " on Unix tempfiles are automatically deleted when Vim exits, on Windows
    " they are not deleted
    try
      call delete(s:buf[s:nr].undo_file)
    catch
      echohl WarningMsg
      echom 'traces.vim - ' . v:exception
      echohl None
    endtry
  endif
endfunction

function! s:adjust_cmdheight(cmdl) abort
  let len = strwidth(strtrans(a:cmdl)) + 2
  let col = &columns
  let height = &cmdheight
  if col * height < len
    let &cmdheight=(len / col) + 1
    redraw
  elseif col * (height - 1) >= len && height > s:buf[s:nr].cmdheight
    let &cmdheight=max([(len / col), s:buf[s:nr].cmdheight])
    redraw
  endif
endfunction

function! traces#init(cmdl) abort
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

  if s:buf[s:nr].duration < s:timeout
    let start_time = reltime()
  endif

  if s:buf[s:nr].changed
    let view = winsaveview()
    noautocmd keepjumps silent undo
    let s:buf[s:nr].changed = 0
    let s:highlighted = 1
    call s:restore_marks()
    call winrestview(view)
  endif
  let cmdl = s:evaluate_cmdl([a:cmdl])

  if s:buf[s:nr].duration < s:timeout
    " range preview
    if (!empty(cmdl.cmd.name) || s:buf[s:nr].show_range) && !get(s:, 'entire_file')
      call s:highlight('Visual', cmdl.range.pattern, 100)
      if empty(cmdl.cmd.name)
        call s:highlight('Search', cmdl.range.specifier, 101)
      endif
      call s:pos_range(cmdl.range.end, cmdl.range.specifier)
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
    call s:adjust_cmdheight(a:cmdl)
    if has('nvim')
      redraw
    else
      call winline()
      " after patch 8.0.1449, necessary for linux cui, otherwise highlighting
      " is not drawn properly, fixed by 8.0.1476
      if has('unix') && !has('gui_running') && has("patch-8.0.1449") && !has("patch-8.0.1476")
        silent! call feedkeys("\<left>\<right>", 'tn')
      endif
    endif
  endif

  if exists('start_time')
    let s:buf[s:nr].duration = reltimefloat(reltime(start_time)) * 1000
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
