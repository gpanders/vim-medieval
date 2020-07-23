let s:tempfile = fnamemodify(tempname(), ':h') . '/medieval'
let s:fences = [{'start': '[`~]\{3,}'}, {'start': '\$\$'}]

augroup medieval
    autocmd!
    autocmd VimLeave * call delete(s:tempfile)
augroup END

" Generate search pattern to match the start of any valid fence
function! s:fencepat(fences)
    return join(map(copy(a:fences), 'v:val.start'), '\|')
endfunction

" Search for a target code block with the given name
function! s:search(target, fences)
    let pat = '^\s*<!--\s*name:\s*' . a:target

    " Trailing characters allowed, e.g. a closing comment tag: '-->'
    let pat .= '\%(\s*\|\s\+.*\)$\n'

    " Search start of following line for opening delimiter of a code fence
    let pat .= '^\s*\%(' . s:fencepat(a:fences) . '\)'

    return search(pat, 'nw')
endfunction

" Wrapper around job start functions for both neovim and vim
function! s:jobstart(cmd, cb)
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

function! s:error(msg)
    if empty(a:msg)
        return
    endif

    echohl ErrorMsg
    echom 'medieval: ' . a:msg
    echohl None
endfunction

function! s:callback(context, output)
    call delete(a:context.tempfile)

    let target = a:context.target
    let start = a:context.start
    let end = a:context.end

    if empty(a:output)
        return
    endif

    let view = winsaveview()

    if target !=# ''
        if target ==# 'self'
            call deletebufline('%', start + 1, end - 1)
            call append(start, a:output)
        elseif target =~# '^@'
            call setreg(target[1], a:output)
        else
            let fences = extend(s:fences, get(g:, 'medieval_fences', []))
            let l = s:search(target, fences)
            if l
                call cursor(l + 1, 1)
                let start = matchlist(getline('.'), '^\s*\(' . s:fencepat(fences) . '\)')

                let endpat = ''
                for fence in fences
                    if start[1] =~# fence.start
                        " If 'end' pattern is not defined, copy the opening
                        " delimiter
                        let endpat = get(fence, 'end', start[1])

                        " Replace any instances of \0, \1, \2, ... with the
                        " submatch from the opening delimiter
                        let endpat = substitute(endpat, '\\\(\d\)', '\=start[1 + submatch(1)]', 'g')
                        break
                    endif
                endfor

                let end = search('^\s*' . endpat . '\s*$', 'nW')
                if !end
                    call winrestview(view)
                    return s:error('No closing fence delimiter found!')
                endif

                call deletebufline('%', l + 2, end - 1)
                call append(l + 1, a:output)
            endif
        endif
    else
        call writefile(a:output, s:tempfile)
        exec 'pedit ' . s:tempfile
    endif

    call winrestview(view)
endfunction

function! medieval#eval(bang, ...)
    if !exists('g:medieval_langs')
        call s:error('g:medieval_langs is unset')
        return
    endif

    let view = winsaveview()
    let line = line('.')
    let start = search('^\s*[`~]\{3,}\s*\%({\.\)\?{\?\a\+,\?.*}\?', 'bnW')
    if !start
        return
    endif

    call cursor(start, 1)
    let [fence, lang] = matchlist(getline(start),
                \ '^\s*\([`~]\{3,}\)\s*\%({\.\)\?{\?\(\a\+\)\?,\?.*}\?')[1:2]
    let end = search('^\s*' . fence . '\s*$', 'nW')
    let langidx = index(map(copy(g:medieval_langs), 'split(v:val, "=")[0]'), lang)

    if end < line || langidx < 0
        call winrestview(view)
        return
    endif

    if v:register !=# '' && v:register !=# '"'
        let target = '@' . v:register
    else
        let target = get(matchlist(getline(start - 1),
                    \ '^\s*<!--\s*target:\s*\([0-9A-Za-z_+.$#&-]\+\)'), 1, '')
    endif

    if g:medieval_langs[langidx] =~# '='
        let lang = split(g:medieval_langs[langidx], '=')[-1]
    endif

    if !executable(lang)
        call winrestview(view)
        return s:error('Command not found: ' . lang)
    endif

    let block = getline(start + 1, end - 1)
    let tmp = tempname()
    call writefile(block, tmp)

    let context = {
                \ 'target': a:bang ? 'self' : a:0 ? a:1 : target,
                \ 'start': start,
                \ 'end': end,
                \ 'tempfile': tmp,
                \ }

    call s:jobstart([lang, tmp], function('s:callback', [context]))
    call winrestview(view)
endfunction
