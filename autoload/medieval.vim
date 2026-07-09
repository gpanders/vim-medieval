const s:fences = [#{start: '\([`~]\{3,}\)\s*\%({\s*\.\?\)\?\(\a\+\)\?', end: '\1', lang: 2,}, #{start: '\$\$'}]
let s:opts = ['name', 'target', 'require', 'tangle', 'session']
let s:optspat = '\(' . join(s:opts, '\|') . '\):\s*\([0-9A-Za-z_+.$#&/-]\+\)'
let s:optionfmt = '<!-- %s -->'
let s:optionpat = '^\s*<!--\s*'

function! s:error(msg) abort
    if empty(a:msg)
        return
    endif

    echohl ErrorMsg
    echom 'medieval: ' . a:msg
    echohl None
endfunction

" Check the v:register variable for a valid value to see if the user wants to
" copy output to a register
function! s:validreg(reg) abort
    if a:reg ==# ''
        return v:false
    endif

    if a:reg ==# '"'
        return v:false
    endif

    if &clipboard =~# '^unnamed' && (a:reg ==# '*' || a:reg ==# '+')
        return v:false
    endif

    return v:true
endfunction

" Generate search pattern to match the start of any valid fence
function! s:fencepat(fences) abort
    return join(map(copy(a:fences), 'v:val.start'), '\|')
endfunction

" Find a code block with the given name and return the start and end lines.
" For example, s:findblock('foo') will find the following block:
"
"     <!-- name: foo -->
"     ```
"     ```
function! s:findblock(ft, name) abort
    let fences = s:fences + get(g:, 'medieval_fences', [])
    let fencepat = s:fencepat(fences)

    let curpos = getcurpos()[1:]

    call cursor(1, 1)

    let pat = get(get(g:, 'medieval_option_pat', {}), a:ft, s:optionpat)
    while 1
        let start = search(pat . s:optspat, 'cW')
        if !start || start == line('$')
            call cursor(curpos)
            return [0, 0]
        endif

        " Move the cursor so that we don't match on the current line again
        call cursor(start + 1, 1)

        if getline(start) =~# '\<name:\s*' . a:name
            if getline('.') =~# '^\s*\%(' . fencepat . '\)'
                break
            endif
        endif
    endwhile

    let endpat = ''
    for fence in fences
        let matches = matchlist(getline('.'), fence.start)
        if !empty(matches)
            " If 'end' pattern is not defined, copy the opening
            " delimiter
            let endpat = get(fence, 'end', fence.start)

            " Replace any instances of \0, \1, \2, ... with the
            " submatch from the opening delimiter
            let endpat = substitute(endpat, '\\\(\d\)', '\=matches[submatch(1)]', 'g')
            break
        endif
    endfor

    let end = search('^\s*' . endpat . '\s*$', 'nW')

    call cursor(curpos)

    return [start, end]
endfunction

function! s:createblock(ft, start, name, fence) abort
    let opt = printf('name: %s', a:name)
    let marker = printf(get(get(g:, 'medieval_option_fmt', {}), a:ft, s:optionfmt), opt)
    call append(a:start, ['', marker, a:fence.start, a:fence.end])
endfunction

function! s:extend(list, val)
    let data = a:val
    if data[-1] == ''
        let data = data[:-2]
    end
    return extend(a:list, data)
endfunction

" Wrapper around job start functions for both neovim and vim
function! s:jobstart(cmd, cb) abort
    let output = []
    if !get(g:, 'medieval_sync') && exists('*jobstart')
        call jobstart(a:cmd, {
                    \ 'on_stdout': {_, data, ... -> s:extend(output, data)},
                    \ 'on_stderr': {_, data, ... -> s:extend(output, data)},
                    \ 'on_exit': {... -> a:cb(output)},
                    \ 'stdout_buffered': 1,
                    \ 'stderr_buffered': 1,
                    \ })
    elseif !get(g:, 'medieval_sync') && exists('*job_start')
        call job_start(a:cmd, {
                    \ 'callback': {_, data -> add(output, data)},
                    \ 'exit_cb': {... -> a:cb(output)},
                    \ })
    elseif exists('*systemlist')
        let output = systemlist(join(a:cmd))
        call a:cb(output)
    else
        call s:error('Unable to start job')
    endif
endfunction

" Parse an options string on the given line number
function! s:parseopts(ft, lnum) abort
    let opts = {}
    let line = getline(a:lnum)
    let pat = get(get(g:, 'medieval_option_pat', {}), a:ft, s:optionpat)
    if line =~# pat . s:optspat
        let cnt = 0
        while 1
            let matches = matchlist(line, s:optspat, 0, cnt)
            if empty(matches)
                break
            endif
            let opts[matches[1]] = matches[2]
            let cnt += 1
        endwhile
    endif

    return opts
endfunction

function! s:require(ft, name) abort
    let [start, end] = s:findblock(a:ft, a:name)
    if !end
        return []
    endif

    let block = getline(start + 2, end - 1)

    let opts = s:parseopts(a:ft, start)
    if has_key(opts, 'require')
        return s:require(a:ft, opts.require) + block
    endif

    return block
endfunction

function! s:callback(context, output) abort
    let opts = a:context.opts
    if !has_key(opts, 'tangle')
        call delete(a:context.fname)
    endif

    if empty(a:output)
        return
    endif

    if has_key(opts, 'complete')
        call opts.complete(a:context, a:output)
    endif

    let start = a:context.start
    let end = a:context.end

    if get(opts, 'target', '') !=# ''
        if opts.target ==# 'self'
            call deletebufline('%', start + 1, end - 1)
            call append(start, a:output)
        elseif opts.target =~# '^@'
            call setreg(opts.target[1], a:output)
        elseif expand(opts.target) =~# '/'
            let f = fnamemodify(expand(opts.target), ':p')
            call writefile(a:output, f)
            echo 'Output written to ' . f
        else
            let [tstart, tend] = s:findblock(a:context.filetype, opts.target)
            if !tstart
                call s:createblock(a:context.filetype, end, opts.target, #{start: getline(start), end: getline(end)})
                let tstart = end + 2
                let tend = tstart + 1
            endif

            if !tend
                return s:error('Block "' . opts.target . '" doesn''t have a closing fence')
            endif

            call deletebufline('%', tstart + 2, tend - 1)
            call append(tstart + 1, a:output)
        endif
    else
        " Open result in scratch buffer
        if &splitbelow
            botright new
        else
            topleft new
        endif

        call append(0, a:output)
        call deletebufline('%', '$')
        exec 'resize' &previewheight
        setlocal buftype=nofile bufhidden=delete nobuflisted noswapfile winfixheight
        wincmd p
    endif

    if has_key(opts, 'after')
        call opts.after(a:context, a:output)
    endif
endfunction

function! medieval#evalrange(line1, line2, target) abort
    if !exists('g:medieval_langs')
        call s:error('g:medieval_langs is unset')
        return
    endif

    let fences = filter((s:fences + get(g:, 'medieval_fences', [])), 'has_key(v:val, "lang")')
    let view = winsaveview()

    " Collect opening fence lines with a language within the range
    let blocks = []
    let lnum = a:line1
    while lnum <= a:line2
        let line = getline(lnum)
        for fence in fences
            let matches = matchlist(line, fence.start)
            if !empty(matches) && matches[fence.lang] !=# ''
                " Skip named blocks without a target — these are output
                " destinations or dependency blocks, not source blocks
                let opts = s:parseopts(&filetype, lnum - 1)
                if !has_key(opts, 'name') || has_key(opts, 'target')
                    call add(blocks, lnum)
                endif
                break
            endif
        endfor
        let lnum += 1
    endwhile

    " Evaluate each block
    for blnum in blocks
        call cursor(blnum, 1)
        call medieval#eval(a:target)
    endfor

    call winrestview(view)
endfunction

function! s:session_read(key, lines) abort
    if !has_key(s:active_sessions, a:key)
        return
    endif

    let session = s:active_sessions[a:key]

    if type(a:lines) == v:t_list
        let data = a:lines
        if !empty(data) && data[-1] ==# ''
            let data = data[:-2]
            let session.buffer += data
        endif
    else
        let session.buffer += [a:lines]
    endif


    if !empty(session.token) && match(session.buffer, session.token) >= 0
        let output = session.buffer
        let token = session.token
        let context = session.context

        let session.token = ''
        let session.context = {}

        let token_idx = match(output, token)
        if token_idx > 0
            let output = output[:token_idx - 1]
        elseif token_idx == 0
            let output = []
        endif

        call context.cb(output)
    endif
endfunction

function! s:vim_cb(channel, msg) abort
    for [k, s] in items(s:active_sessions)
        if s.id == a:channel
            call s:session_read(k, a:msg)
            break
        endif
    endfor
endfunction

function! s:nvim_cb(job_id, data, event) abort
    for [k, s] in items(s:active_sessions)
        if s.id == a:job_id
            call s:session_read(k, a:data)
            break
        endif
    endfor
endfunction

function! s:nvim_session_exit_cb(job_id, exit_code, event) abort
    for [k, s] in items(s:active_sessions)
        if s.id == a:job_id
            call remove(s:active_sessions, k)
            break
        endif
    endfor
endfunction

function! s:eval_session(lang, session_name, block, cb) abort
    if !exists('s:active_sessions')
        let s:active_sessions = {}
    endif

    if !exists('s:session_buffers')
        let s:session_buffers = {}
    endif

    let key = a:lang . ':' . a:session_name
    let eof_token = '__MEDIEVAL_SESSION_EOF__' . reltimestr(reltime())
    let running = has_key(s:active_sessions, key)

    if running
        let session = s:active_sessions[key]
        if !has('nvim')
            let running = job_status(session.job) ==# 'run'
        endif
    endif

    if !running
        let cmd = [a:lang]
        if a:lang ==# 'python' || a:lang ==# 'python3'
            let cmd += ['-i', '-q']
        endif

        if has('nvim')
            let id = jobstart(cmd, {
                        \ 'on_stdout': function('s:nvim_cb'),
                        \ 'on_stderr': function('s:nvim_cb'),
                        \ 'on_exit': function('s:nvim_session_exit_cb'),
                        \ 'stdout_buffered': 0,
                        \ 'stderr_buffered': 0,
                        \ })
            if id <= 0
                return s:error('Failed to start job for ' . a:lang)
            endif
            let s:active_sessions[key] = {
                        \ 'id': id,
                        \ 'buffer': [],
                        \ 'token': '',
                        \ 'context': {},
                        \ }
        else
            let job = job_start(l:cmd, {
                        \ 'out_cb': function('s:vim_cb'),
                        \ 'err_cb': function('s:vim_cb'),
                        \ 'mode': 'nl',
                        \ })
            let s:active_sessions[key] = {
                        \ 'id': job_getchannel(job),
                        \ 'job': job,
                        \ 'buffer': [],
                        \ 'token': '',
                        \ 'context': {},
                        \ }
        endif
    endif

    let session = s:active_sessions[key]
    let session.buffer = []
    let session.token = eof_token
    let session.context = {'cb': a:cb}

    let new_block = copy(a:block)
    if a:lang =~# 'python'
        let new_block += ['print("' . eof_token . '")']
    else
        let new_block += ['echo "' . eof_token . '"']
    endif

    if has('nvim')
        call chansend(session.id, new_block + [''])
    else
        for line in new_block
            call ch_sendraw(session.id, line . "\n")
        endfor
    endif
endfunction

function! medieval#eval(...) abort
    if !exists('g:medieval_langs')
        call s:error('g:medieval_langs is unset')
        return
    endif

    let view = winsaveview()
    let line = line('.')
    let fences = filter((s:fences + get(g:, 'medieval_fences', [])), 'has_key(v:val, "lang")')
    let fencepat = s:fencepat(fences)
    let start = search(fencepat, 'bcnW')
    if !start
        return
    endif

    " If cursor is in a named destination block, find and evaluate its source
    let opts = s:parseopts(&filetype, start - 1)
    if has_key(opts, 'name') && !has_key(opts, 'target')
        call cursor(1, 1)
        let pat = get(get(g:, 'medieval_option_pat', {}), &filetype, s:optionpat)
        while 1
            let srcline = search(pat . s:optspat, 'cW')
            if !srcline
                call winrestview(view)
                return s:error('No source block targeting "' . opts.name . '"')
            endif
            call cursor(srcline + 1, 1)
            if getline(srcline) =~# '\<target:\s*' . opts.name
                break
            endif
        endwhile
        call call('medieval#eval', a:000)
        call winrestview(view)
        return
    endif

    call cursor(start, 1)

    let lang = ''
    let endpat = ''
    for fence in fences
        let matches = matchlist(getline(start), fence.start)
        if !empty(matches)
            let lang = matches[fence.lang]
            let endpat = get(fence, 'end', fence.start)
            let endpat = substitute(endpat, '\\\(\d\)', '\=matches[submatch(1)]', 'g')
            break
        endif
    endfor

    if empty(lang)
        call winrestview(view)
        return s:error('Could not determine language for block')
    endif

    if empty(endpat)
        call winrestview(view)
        return s:error('No end pattern')
    endif

    let end = search('^\s*' . endpat . '\s*$', 'nW')
    if end < line
        call winrestview(view)
        return s:error('Closing fence not found')
    endif

    let langidx = index(map(copy(g:medieval_langs), 'split(v:val, "=", 1)[0]'), lang)
    if langidx < 0
        call winrestview(view)
        echo '''' . lang . ''' not found in g:medieval_langs'
        return
    endif

    let opts = s:parseopts(&filetype, start - 1)

    if a:0 && a:1 !=# ''
        let opts.target = a:1
    elseif s:validreg(v:register)
        let opts.target = '@' . v:register
    endif

    if g:medieval_langs[langidx] =~# '='
        let lang = split(g:medieval_langs[langidx], '=')[-1]
    endif

    if !executable(lang)
        call winrestview(view)
        return s:error('Command not found: ' . lang)
    endif

    if has_key(opts, 'tangle')
        let fname = expand(opts.tangle)
        echo 'Tangled source code written to ' . fname
    else
        let fname = tempname()
        if lang == "cmd"
            let fname .= ".bat"
        endif
    endif

    if a:0 > 1
        call extend(opts, a:2, 'error')
    endif

    let context = {'opts': opts, 'start': start, 'end': end, 'fname': fname, 'filetype': &filetype}

    let block = getline(start + 1, end - 1)
    if has_key(opts, 'require')
        let block = s:require(&filetype, opts.require) + block
    endif
    if has_key(opts, 'setup')
        call opts.setup(context, block)
    endif

    if has_key(opts, 'session')
        call s:eval_session(lang, opts.session, block, function('s:callback', [context]))
    else
        call writefile(block, fname)
        if lang == "cmd"
            call s:jobstart([fname], function('s:callback', [context]))
        else
            call s:jobstart([lang, fname], function('s:callback', [context]))
        endif
    endif
    call winrestview(view)
endfunction
