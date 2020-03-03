command! -bang -buffer -nargs=? EvalBlock call medieval#eval(<bang>0, <f-args>)
let b:undo_ftplugin = get(b:, 'undo_ftplugin', '') . '|delc EvalBlock'
