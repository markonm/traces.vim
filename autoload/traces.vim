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
                \ . 'a%[ppend][[:alnum:]]@!\!=|'
                \ . 'c%[hange][[:alnum:]]@!\!=|'
                \ . 'cal%[l][[:alnum:]]@!|'
                \ . 'ce%[nter][[:alnum:]]@!|'
                \ . 'co%[py][[:alnum:]]@!|'
                \ . 'd%[elete][[:alnum:]]@!|'
                \ . 'diffg%[et][[:alnum:]]@!|'
                \ . 'diffpu%[t][[:alnum:]]@!|'
                \ . 'dj%[ump][[:alnum:]]@!\!=|'
                \ . 'dli%[st][[:alnum:]]@!\!=|'
                \ . 'ds%[earch][[:alnum:]]@!\!=|'
                \ . 'dsp%[lit][[:alnum:]]@!\!=|'
                \ . 'exi%[t][[:alnum:]]@!\!=|'
                \ . 'fo%[ld][[:alnum:]]@!|'
                \ . 'foldc%[lose][[:alnum:]]@!\!=|'
                \ . 'foldd%[oopen][[:alnum:]]@!|'
                \ . 'folddoc%[losed][[:alnum:]]@!|'
                \ . 'foldo%[pen][[:alnum:]]@!\!=|'
                \ . 'g%[lobal][[:alnum:]]@!\!=|'
                \ . 'ha%[rdcopy][[:alnum:]]@!\!=|'
                \ . 'i%[nsert][[:alnum:]]@!\!=|'
                \ . 'ij%[ump][[:alnum:]]@!\!=|'
                \ . 'il%[ist][[:alnum:]]@!\!=|'
                \ . 'is%[earch][[:alnum:]]@!\!=|'
                \ . 'isp%[lit][[:alnum:]]@!\!=|'
                \ . 'j%[oin][[:alnum:]]@!\!=|'
                \ . 'k[[:alnum:]]@!|'
                \ . 'l%[ist][[:alnum:]]@!|'
                \ . 'le%[ft][[:alnum:]]@!|'
                \ . 'le%[ft][[:alnum:]]@!|'
                \ . 'luado[[:alnum:]]@!|'
                \ . 'luafile[[:alnum:]]@!|'
                \ . 'lua[[:alnum:]]@!|'
                \ . 'm%[ove][[:alnum:]]@!|'
                \ . 'ma%[rk][[:alnum:]]@!|'
                \ . 'mz%[scheme][[:alnum:]]@!|'
                \ . 'mzf%[ile][[:alnum:]]@!|'
                \ . 'norm%[al][[:alnum:]]@!\!=|'
                \ . 'nu%[mber][[:alnum:]]@!|'
                \ . 'p%[rint][[:alnum:]]@!|'
                \ . 'perld%[o][[:alnum:]]@!|'
                \ . 'ps%[earch][[:alnum:]]@!\!=|'
                \ . 'py%[thon][[:alnum:]]@!|'
                \ . 'py%[thon][[:alnum:]]@!|'
                \ . 'pydo[[:alnum:]]@!|'
                \ . 'pyf%[ile][[:alnum:]]@!|'
                \ . 'r%[ead][[:alnum:]]@!|'
                \ . 'ri%[ght][[:alnum:]]@!|'
                \ . 'rubyd%[o][[:alnum:]]@!|'
                \ . 's%[ubstitute][[:alnum:]]@!|'
                \ . 'sm%[agic][[:alnum:]]@!|'
                \ . 'sno%[magic][[:alnum:]]@!|'
                \ . 'sor%[t][[:alnum:]]@!\!=|'
                \ . 'tc%[l][[:alnum:]]@!|'
                \ . 'tcld%[o][[:alnum:]]@!|'
                \ . 'ter%[minal][[:alnum:]]@!|'
                \ . 't[[:alnum:]]@!|'
                \ . 'up%[date][[:alnum:]]@!\!=|'
                \ . 'v%[global][[:alnum:]]@!|'
                \ . 'w%[rite][[:alnum:]]@!\!=|'
                \ . 'wq[[:alnum:]]@!\!=|'
                \ . 'x%[it][[:alnum:]]@!\!=|'
                \ . 'y%[ank][[:alnum:]]@!|'
                \ . 'z\#|'
                \ . 'z[[:alnum:]]@!'
                \ . ')'

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

function! s:spec_to_abs(address, last_position) abort
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
    if !query
      let result.valid = 0
    endif
    call add(result.range, query)
    let s:buf[s:nr].show_range = 1
    let result.regex = pattern

  elseif a:address.address =~# '^?.*$'
    let pattern = a:address.address[1:]
    let pattern = substitute(pattern, '\\?', '?', '')
    call cursor(a:last_position, 1)
    silent! let query = search(pattern, 'nb', 0, s:s_timeout)
    if !query
      let result.valid = 0
    endif
    call add(result.range, query)
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
      " skip empty unclosed pattern specifier when range is empty otherwise
      " substitute it with current position
      if address.address =~# '^[?/]$'
        let s:buf[s:nr].show_range = 1
        if empty(result.range)
          break
        endif
        let address.address = '.'
      endif
      let query = s:spec_to_abs(address, tmp_pos)
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
    let start = a:cmdl.range.end - 1
    let end   = a:cmdl.range.end + 1
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

function! s:parse_sort(cmdl) abort
  call s:trim(a:cmdl.string)
  let pattern = '\v^.{-}([[:graph:]]&[^[:alnum:]\\"|])(%(\\.|.){-})%((\1)|$)'
  let args = {}
  let r = matchlist(a:cmdl.string[0], pattern)
  if len(r)
    let args.delimiter = r[1]
    let args.pattern   = s:add_flags((empty(r[2]) && !empty(r[3])) ? s:last_pattern : r[2], a:cmdl, 1)
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
  if exists('s:buf[s:nr].pre_cmdl_view')
    if get(s:buf[s:nr].pre_cmdl_view, 'mode', '') =~# "^[vV\<C-V>]"
          \ && (a:end > line('w$') || a:end < line('w0'))
      unlet s:buf[s:nr].pre_cmdl_view.mode
      call winrestview(s:buf[s:nr].pre_cmdl_view)
    endif
    unlet s:buf[s:nr].pre_cmdl_view
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

  if &hlsearch && !empty(a:pattern) && a:group ==# 'TracesSearch'
    noautocmd let &hlsearch = 0
  endif
  if &scrolloff !=# 0
    let scrolloff = &scrolloff
    noautocmd let &scrolloff = 0
  endif
  if &winwidth isnot 1
    noautocmd set winwidth=1
  endif
  if &winheight isnot 1
    noautocmd set winheight=1
  endif

  let windows = filter(win_findbuf(s:nr), {_, val -> win_id2win(val)})
  for id in windows
    let wininfo = getwininfo(id)[0]
    if wininfo.height is 0 || wininfo.width is 0
      " skip minimized windows
      continue
    endif
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
        silent! call matchdelete(s:win[id].hlight[a:group].index)
      endif
      let s:win[id].hlight[a:group].pattern = a:pattern
      silent! let s:win[id].hlight[a:group].index = matchadd(a:group, a:pattern, a:priority)
      let s:highlighted = 1
    endif
    if (&conceallevel !=# 2 || &concealcursor !=# 'c') && a:group ==# 'Conceal'
      let s:win[id].options = get(s:win[id], 'options', {})
      let s:win[id].options.conceallevel = &conceallevel
      let s:win[id].options.concealcursor = &concealcursor
      noautocmd set conceallevel=2
      noautocmd set concealcursor=c
    endif
    " highlighting doesn't work properly when cursorline or cursorcolumn is
    " enabled
    if &cursorcolumn || &cursorline
      let s:win[id].options = get(s:win[id], 'options', {})
      let s:win[id].options.cursorcolumn = &cursorcolumn
      let s:win[id].options.cursorline = &cursorline
      noautocmd set nocursorcolumn
      noautocmd set nocursorline
    endif
  endfor
  if bufname('%') !=# '[Command Line]'
    noautocmd call win_gotoid(cur_win)
  endif
  if exists('scrolloff')
    noautocmd let &scrolloff = scrolloff
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
  let l_dlm = a:cmdl.cmd.args.last_delimiter

  call s:pos_pattern(ptrn, range, dlm, 1)

  if !g:traces_substitute_preview || &readonly || !&modifiable || empty(str) && empty(l_dlm)
    call s:highlight('TracesSearch', ptrn, 101)
    return
  endif

  call s:save_undo_history()

  if s:buf[s:nr].undo_file is 0
    call s:highlight('TracesSearch', ptrn, 101)
    return
  endif

  let cmd = 'noautocmd keepjumps keeppatterns ' . s:format_command(a:cmdl)
  let tick = b:changedtick

  let lines = line('$')
  let view = winsaveview()
  let ul = &undolevels
  noautocmd let &undolevels = 0
  silent! execute cmd
  noautocmd let &undolevels = ul

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
  call s:highlight('TracesSearch', s:buf[s:nr].s_mark . '\_.\{-}' . s:buf[s:nr].s_mark, 101)
  call s:highlight('Conceal', s:buf[s:nr].s_mark . '\|' . s:buf[s:nr].s_mark, 102)
endfunction

function! s:preview_global(cmdl) abort
  if empty(a:cmdl.range.specifier) && has_key(a:cmdl.cmd.args, 'pattern')
    call s:highlight('TracesSearch', a:cmdl.cmd.args.pattern, 101)
    call s:pos_pattern(a:cmdl.cmd.args.pattern, a:cmdl.range.abs, a:cmdl.cmd.args.delimiter, 0)
  endif
endfunction

function! s:preview_sort(cmdl) abort
  if empty(a:cmdl.range.specifier) && has_key(a:cmdl.cmd.args, 'pattern')
    call s:highlight('TracesSearch', a:cmdl.cmd.args.pattern, 101)
    call s:pos_pattern(a:cmdl.cmd.args.pattern, a:cmdl.range.abs, a:cmdl.cmd.args.delimiter, 0)
  endif
endfunction

function! s:cmdl_enter(view) abort
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
  let s:buf[s:nr].empty_undotree = empty(undotree().entries)
  let s:buf[s:nr].changed = 0
  let s:buf[s:nr].cmdheight = &cmdheight
  let s:buf[s:nr].redraw = 1
  let s:buf[s:nr].s_mark = (&encoding == 'utf-8' ? "\uf8b4" : '' )
  let s:buf[s:nr].winrestcmd = winrestcmd()
  let s:buf[s:nr].alt_win = win_getid(winnr('#'))
  let s:buf[s:nr].winwidth = &winwidth
  let s:buf[s:nr].winheight = &winheight
  let s:buf[s:nr].pre_cmdl_view = a:view
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
      noautocmd let &scrolloff = 0
    endif
    let cur_win = win_getid()
    let alt_win = win_getid(winnr('#'))
    let windows = filter(win_findbuf(s:nr), {_, val -> win_id2win(val)})
    for id in windows
      let wininfo = getwininfo(id)[0]
      if wininfo.height is 0 || wininfo.width is 0
        " skip minimized windows
        continue
      endif
      noautocmd call win_gotoid(id)
      if exists('s:win[id]')
        if exists('s:win[id].hlight')
          for group in keys(s:win[id].hlight)
            if s:win[id].hlight[group].index !=# - 1
              silent! call matchdelete(s:win[id].hlight[group].index)
            endif
          endfor
        endif
        if exists('s:win[id].options')
          for option in keys(s:win[id].options)
            execute 'noautocmd let &' . option . '="' . s:win[id].options[option] . '"'
          endfor
        endif
        unlet s:win[id]
      endif
    endfor
    if bufname('%') !=# '[Command Line]'
      noautocmd call win_gotoid(s:buf[s:nr].alt_win)
      noautocmd call win_gotoid(cur_win)
    endif
    if exists('scrolloff')
      noautocmd let &scrolloff = scrolloff
    endif
  endif

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

function! s:save_undo_history() abort
  if exists('s:buf[s:nr].undo_file')
    return
  endif
  if bufname('%') ==# '[Command Line]' || s:buf[s:nr].empty_undotree
    let s:buf[s:nr].undo_file = 1
    return
  endif

  let s:buf[s:nr].undo_file = tempname()
  let start_time = reltime()
  noautocmd silent execute 'wundo ' . s:buf[s:nr].undo_file
  if !filereadable(s:buf[s:nr].undo_file)
    let s:buf[s:nr].undo_file = 0
    return
  endif
  if (reltimefloat(reltime(start_time)) * 1000) > s:timeout
    call delete(s:buf[s:nr].undo_file)
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
  call delete(s:buf[s:nr].undo_file)
endfunction

function! s:adjust_cmdheight(cmdl) abort
  let len = strwidth(strtrans(a:cmdl)) + 2
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

  " skip leading colon
  let cmdl = substitute(cmdl, '\v^:+', '', '')

  " skip modifiers
  let pattern = '\v^\s*%('
        \ . 'sil%[ent]\!=|'
        \ . 'verb%[ose]|'
        \ . 'noa%[utocmd]|'
        \ . 'loc%[kmarks]'
        \ . 'keepp%[atterns]|'
        \ . 'keepa%[lt]|'
        \ . 'keepj%[umps]|'
        \ . 'kee%[pmarks]|'
        \ . ')\s+'
  while 1
    let offset = matchstrpos(cmdl, pattern)
    if offset[2] isnot -1
      let cmdl = strcharpart(cmdl, offset[2])
    else
      break
    endif
  endwhile

  if g:traces_skip_modifiers
    " skip *do modifiers
    let cmdl = substitute(cmdl,
          \ '\v^\s*%(%(%(\d+|\.|\$|\%)\s*[,;]=\s*)+)=\s*%(cdo|cfdo|ld%[o]|lfdo'
          \ . '|bufd%[o]|tabd%[o]|argdo|wind%[o])\!=\s+', '', '')

    " skip modifiers
    while 1
      let offset = matchstrpos(cmdl, pattern)
      if offset[2] isnot -1
        let cmdl = strcharpart(cmdl, offset[2])
      else
        break
      endif
    endwhile
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
  let cmdl = s:evaluate_cmdl([s:skip_modifiers(a:cmdl)])

  if s:buf[s:nr].duration < s:timeout
    " range preview
    if (!empty(cmdl.cmd.name) || s:buf[s:nr].show_range) && !get(s:, 'entire_file')
      call s:highlight('Visual', cmdl.range.pattern, 100)
      if empty(cmdl.cmd.name)
        call s:highlight('TracesSearch', cmdl.range.specifier, 101)
      endif
      call s:pos_range(cmdl.range.end, cmdl.range.specifier)
    endif

    " cmd preview
    if cmdl.cmd.name =~# '\v^%(s%[ubstitute]|sm%[agic]|sno%[magic])$'
      call s:preview_substitute(cmdl)
    elseif cmdl.cmd.name =~# '\v^%(g%[lobal]\!=|v%[global])$'
      call s:preview_global(cmdl)
    elseif cmdl.cmd.name =~# '\v^%(sor%[t]\!=)$'
      call s:preview_sort(cmdl)
    endif

    " clear unnecessary hl
    if empty(cmdl.range.pattern) || get(s:, 'entire_file')
      call s:highlight('Visual', '', 100)
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

  " update screen if necessary
  if s:highlighted
    call s:adjust_cmdheight(a:cmdl)
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
