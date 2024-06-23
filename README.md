# julia-repl-vim

Julia REPL plugin for vim/neovim

https://user-images.githubusercontent.com/30594/166437124-f81fc776-c72c-4332-990f-10ba3b9dbaf1.mov

## Usage

Install the support Julia package:
```
using Pkg
Pkg.add(url="https://github.com/andreypopp/julia-repl-vim")
```

Now when you start `julia` you can do:
```
using REPLVim
@async REPLVim.serve()
```
this starts a REPL server (default port 2345) the editor can connect to.

to start on a specific port run:

```
@async REPLVim.serve(<portnumber>)
```

In your `.vimrc`:
```
Plug 'andreypopp/julia-repl-vim'
```
to install the editor plugin.

In editor to connect to the REPL server:
```
:JuliaREPLConnect <portno>
```


Now `<leader>e` will eval the current line or the current selection in REPL as
if you typed it directly.

REPL completions are also available,but not enabled by default. Enable with
```
let g:julia_repl_complete=1
```
in your vimrc


The `<C-x><C-o>` omni completion will query REPL for
completions.


## Credits

REPL server code is based on [RemoteREPL.jl] project.

[RemoteREPL.jl]: https://github.com/c42f/RemoteREPL.jl
