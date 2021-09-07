# vim-medieval

Evaluate Markdown code blocks within Vim.

[![asciicast](https://asciinema.org/a/306995.svg)](https://asciinema.org/a/306995)

## Table of Contents

- [Description](#description)
- [Block Dependencies](#block-dependencies)
- [Code Tangling](#code-tangling)
- [Configuration](#configuration)
- [Create a mapping](#create-a-mapping)
- [Limitations](#limitations)
- [Contributing](#contributing)

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

You can also redirect the output of the evaluation into a register using
`:EvalBlock @{0-9a-z".=*+}`.

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

The target of a block can also be a file. If the target name contains a `/`
character, it is assumed to be a file path. File paths can contain environment
variables and tilde expansion. Example:

````markdown
<!-- target: $HOME/squares.txt -->
```python
print([x*x for x in range(5)])
```
````

Note that the following will write to a code block named `squares.txt` (and
create it if it doesn't exist) instead of writing to a file called
`squares.txt`:

```markdown
<!-- target: squares.txt -->
```

To write to a file called `squares.txt`, use

```markdown
<!-- target: ./squares.txt -->
```

You can manually specify a target block using `:EvalBlock {target}`. With
`[!]`, `:EvalBlock` will cause the evaluated code block to replace its own
contents with the result of its evaluation:

````markdown
```sh
fortune
```
````

After `:EvalBlock!`:

````markdown
```sh
The difference between art and science is that science is what we
understand well enough to explain to a computer.  Art is everything else.
                -- Donald Knuth, "Discover"
```
````

The language of the block being executed is detected through the text next to
the opening code fence (known as the "info string"). There is no formal
specification for how the info string should be formatted; however, Medieval
can detect info strings in any of the following formats:

````markdown
```lang
```

```{.lang}
```

```{lang}
```
````

Whitespace is allowed before the info string. The closing `}` is not required
for the latter two styles, meaning you can use info strings such as

````markdown
``` {.python .numberLines #my-id}
```
````

Note, however, that when using this kind of info string the language name must
be first for Medieval to correctly detect it.

The target block can be either another code block (delimited by `` ``` `` or
`~~~`) or a LaTeX math block (delimited by `$$`):

````markdown
<!-- target: math -->
```python
print(r"\text{Hello LaTeX!}")
```

<!-- name: math -->
$$
\text{Hello LaTeX!}
$$
````

The block labels must be of the form `<!-- OPTION: VALUE[,] [OPTION: VALUE[,]
[...]]` where `OPTION` is one of `name`, `target`, `require`, or `tangle`. The
label can be preceeded by whitespace, but no other characters. The option
values can be composed of the following characters: `0-9A-Za-z_+.$#&-`. Note
that the closing tag of the HTML comment is not required. This allows you to
embed the code block within an HTML block comment so that the block will not be
rendered in the final output. For example:

````markdown
<!-- target: example
```sh
echo '$ ls -1'
ls -1
```
-->

<!-- name: example -->
```sh
$ ls -1
LICENSE
README.md
autoload
doc
ftplugin
```
````

In this example, only the second block will be rendered, since the first block
is nested within an HTML comment.

## Block Dependencies

Code blocks can be combined using the `require` option. The argument to the
`require` option is the name of another code block which will be evaluated
before the contents of the block itself. Required blocks must use the same
language as the requiring block.

For example,

````markdown
<!-- name: numpy -->
```python
import numpy as np
```

<!-- target: output, require: numpy -->
```python
print(np.arange(1, 5))
```

<!-- name: output -->
```
```
````

Running `:EvalBlock` in the second code block produces:

````markdown
<!-- name: output -->
```
[1 2 3 4]
```
````

Blocks can have recursive dependencies:

````markdown
<!-- name: first_name -->
```sh
first_name="Gregory"
```

<!-- name: full_name, require: first_name -->
```sh
full_name="$first_name Anders"
```

<!-- target: greeting, require: full_name -->
```sh
echo "Hi, my name is $full_name"
```

After running :EvalBlock in the block above...

<!-- name: greeting -->
```
Hi, my name is Gregory Anders
```
````

## Code Tangling

The source code in a code block can be written to a given file before executing
by using the "tangle" option. This can be used in conjunction with the
"require" keyword to combine multiple blocks together into a single combined
source file.

Example:

````markdown
<!-- name: numpy -->
```python
import numpy as np
```

<!-- require: numpy tangle: script.py -->
```python
x = np.arange(5)
print(x)
```
````

When you run `:EvalBlock` on the second code block above, a new file called
"script.py" will be generated in your current working directory with the
contents

```python
import numpy as np
x = np.arange(5)
print(x)
```

The file specified as the "tangle" option can be a relative or absolute path
and may use tilde expansion and environment variables.

If you only wish to use the tangling feature without printing the output of the
code block, you can use `/dev/null` as the block target:

```markdown
<!-- target: /dev/null tangle: script.py -->
```

## Configuration

Medieval will only attempt to execute code blocks in languages explicitly
listed in the variable `g:medieval_langs`. The structure of this variable is a
list of strings corresponding to whitelisted languages that can be
interpreted. If a language's interpreter has a different name than the
language itself, you can use the form `{lang}={interpreter}` to specify what
interpreter should be used.

For example, to allow Medieval to run Python, Ruby, and shell scripts, use

```vim
let g:medieval_langs = ['python=python3', 'ruby', 'sh', 'console=bash']
```

By default, `g:medieval_langs` is empty, so you **must** specify this variable
yourself.

You can also define custom code fence delimiters using the variable
`g:medieval_fences`. This variable is a List of Dicts containing a `start` key
that defines a pattern for the opening delimiter of the code block and an
optional `end` key that defines a pattern for the closing delimiter of the code
block. If `end` is omitted, then the closing delimiter is assumed to be the
same as the opening delimiter.

For example, a [Hugo shortcode][shortcodes] has the following form:

```markdown
{{< katex >}}
Some content here
{{< /katex >}}
```

You can use Medieval with blocks like this by setting `g:medieval_fences` to
the following:

```vim
let g:medieval_fences = [{'start': '{{<\s\+\(\S\+\)\s\+>}}', 'end': '{{<\s\+/\1\s\+>}}'}]
```

Note the use of a capture group in the `start` pattern and the use of `\1` in
the end pattern. In this example, the `\1` in the end pattern will be replaced
by whatever matches the capture group in the `start` pattern (`katex` in our
example above).

[shortcodes]: https://gohugo.io/content-management/shortcodes/

## Create a mapping

Medieval does not create any mappings by default, but you can easily create one
yourself by adding the following to the file
`~/.vim/after/ftplugin/markdown.vim` (create it if it does not yet exist):

```vim
nnoremap <buffer> Z! :<C-U>EvalBlock<CR>
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
