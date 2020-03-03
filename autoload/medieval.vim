function! medieval#eval(bang, ...)
    if !exists('g:medieval_langs')
        return
    endif

    let view = winsaveview()
    let line = line('.')
    let start = search('^\s*[`~]\{3,}\s*\%({\.\)\?\a\+', 'bnW')
    if !start
        return
    endif

    call cursor(start, 1)
    let [fence, lang] = matchlist(getline(start), '^\s*\([`~]\{3,}\)\s*\%({\.\)\?\(\a\+\)\?')[1:2]
    let end = search('^\s*' . fence . '\s*$', 'nW')
    let langidx = index(map(copy(g:medieval_langs), 'split(v:val, "=")[0]'), lang)

    if end < line || langidx < 0
        call winrestview(view)
        return
    endif

    if v:register != '"'
        let target = '@' . v:register
    else
        let target = get(matchlist(getline(start - 1), '^\s*<!--\s*target:\s*\(\w\+\)\s*-->'), 1, '')
    endif

    if g:medieval_langs[langidx] !=# lang
        let lang = split(g:medieval_langs[langidx], '=')[1]
    endif

    let block = getline(start + 1, end - 1)
    let tmp = tempname()
    call writefile(block, tmp)
    let output = systemlist(lang . ' ' . tmp)

    let target = a:bang ? 'self' : a:0 ? a:1 : target
    if target != ''
        if target ==# 'self'
            call deletebufline('%', start + 1, end - 1)
            call append(start, output)
        elseif target =~# '^@'
            call setreg(target[1], output)
        else
            let l = search('^\s*<!--\s*name:\s*' . target . '\s*-->\s*$\n^\s*[`~]\{3,}', 'nw')
            if l
                call cursor(l + 1, 1)
                let [fence] = matchlist(getline(l + 1), '^\s*\([`~]\{3,}\)')[1]
                let end = search('^\s*' . fence . '\s*$', 'nW')
                if end
                    call deletebufline('%', l + 2, end - 1)
                    call append(l + 1, output)
                endif
            endif
        endif
    else
        echo join(output, "\n")
    endif

    call winrestview(view)
endfunction
