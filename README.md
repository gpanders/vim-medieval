# vim-medieval

Evaluate Markdown code blocks within Vim.

[![asciicast](https://asciinema.org/a/306995.svg)](https://asciinema.org/a/306995)

## Description

Medieval allows you to evaluate code blocks in Markdown buffers of the
following form:

````markdown
```bash
echo "Hello world!"
```
````

By placing your cursor anywhere in the code block above and running
`:EvalBlock`, Medieval will print the result of evaluating the block (in this
case, it will echo "Hello world!")

You can send the output of evaluation into another code block, allowing
you to do a primitive style of literate programming. You can accomplish this
by adding a "target" parameter to your code block and creating a second code
block with a "name" parameter. The output of the evaluation of your code block
will be redirected to the targeted block. For example:

````markdown
<!-- target: squares -->
```python
print([x*x for x in range(5)])
```

<!-- name: squares -->
```
```
````

If you run `:EvalBlock` in the first code block, the second block will become

````markdown
<!-- name: squares -->
```
[0, 1, 4, 9, 16]
```
````

Medieval can do a lot more. Read `:h medieval` for the full documentation.

## Create a mapping

Medieval does not create any mappings by default, but you can easily create one
yourself by adding the following to the file
`~/.vim/after/ftplugin/markdown.vim` (create it if it does not yet exist):

```vim
nmap <buffer> Z! <Plug>(medieval-eval)
```

## Limitations

For now, Medieval only works in Markdown buffers. If you'd like to see support
added for other file types, please see the [Contributing](#contributing)
section.

## Contributing

Please feel free to contribute changes or bug fixes. You can [send patches][]
to <git@gpanders.com> or submit a pull request on [GitHub][].

[send patches]: https://git-send-email.io/
[Github]: https://github.com/gpanders/vim-medieval
