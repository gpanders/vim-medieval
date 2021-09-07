let s:fences = [{'start': '[`~]\{3,}'}, {'start': '\$\$'}]
let s:opts = ['name', 'target', 'require', 'tangle']
let s:optspat = '\(' . join(s:opts, '\|') . '\):\s*\([0-9A-Za-z_+.$#&/-]\+\)'

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
function! s:findblock(name) abort
    let fences = extend(s:fences, get(g:, 'medieval_fences', []))
    let fencepat = s:fencepat(fences)

    let curpos = getcurpos()[1:]

    call cursor(1, 1)

    while 1
        let start = search('^\s*<!--\s*' . s:optspat, 'cW')
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

    let tstart = matchlist(getline('.'), '^\s*\(' . fencepat . '\)')

    let endpat = ''
    for fence in fences
        if tstart[1] =~# fence.start
            " If 'end' pattern is not defined, copy the opening
            " delimiter
            let endpat = get(fence, 'end', tstart[1])

            " Replace any instances of \0, \1, \2, ... with the
            " submatch from the opening delimiter
            let endpat = substitute(endpat, '\\\(\d\)', '\=tstart[1 + submatch(1)]', 'g')
            break
        endif
    endfor

    let end = search('^\s*' . endpat . '\s*$', 'nW')

    call cursor(curpos)

    return [start, end]
endfunction

function! s:createblock(start, name, fence) abort
    call append(a:start, ['', '<!-- name: ' . a:name . ' -->', a:fence, a:fence])
endfunction

" Wrapper around job start functions for both neovim and vim
function! s:jobstart(cmd, cb) abort
    let output = []
    if exists('*jobstart')
        call jobstart(a:cmd, {
                    \ 'on_stdout': {_, data, ... -> extend(output, data[:-2])},
                    \ 'on_stderr': {_, data, ... -> extend(output, data[:-2])},
                    \ 'on_exit': {... -> a:cb(output)},
                    \ 'stdout_buffered': 1,
                    \ 'stderr_buffered': 1,
                    \ })
    elseif exists('*job_start')
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
function! s:parseopts(lnum) abort
    let opts = {}
    let line = getline(a:lnum)
    if line =~# '^\s*<!--\s*' . s:optspat
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

function! s:require(name) abort
    let [start, end] = s:findblock(a:name)
    if !end
        return []
    endif

    let block = getline(start + 2, end - 1)

    let opts = s:parseopts(start)
    if has_key(opts, 'require')
        return s:require(opts.require) + block
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
            let [tstart, tend] = s:findblock(opts.target)
            if !tstart
                let fence = getline(end)
                call s:createblock(end, opts.target, fence)
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
endfunction

function! medieval#eval(bang, ...) abort
    if !exists('g:medieval_langs')
        call s:error('g:medieval_langs is unset')
        return
    endif

    let view = winsaveview()
    let line = line('.')
    let startpat = '\v^\s*([`~]{3,})\s*%(\{\s*.?)?(\a+)?'
    let start = search(startpat, 'bcnW')
    if !start
        return
    endif

    call cursor(start, 1)
    let [fence, lang] = matchlist(getline(start), startpat)[1:2]
    let end = search('\V\^\s\*' . fence . '\s\*\$', 'nW')
    if end < line
        call winrestview(view)
        return s:error('Closing fence not found')
    endif

    let langidx = index(map(copy(g:medieval_langs), 'split(v:val, "=")[0]'), lang)
    if langidx < 0
        call winrestview(view)
        echo '''' . lang . ''' not found in g:medieval_langs'
        return
    endif

    let opts = s:parseopts(start - 1)

    if a:bang
        let opts.target = 'self'
    elseif a:0
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
    endif

    let block = getline(start + 1, end - 1)
    if has_key(opts, 'require')
        let block = s:require(opts.require) + block
    endif
    call writefile(block, fname)

    let context = {'opts': opts, 'start': start, 'end': end, 'fname': fname}
    call s:jobstart([lang, fname], function('s:callback', [context]))
    call winrestview(view)
endfunction
