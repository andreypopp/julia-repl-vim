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
this starts a REPL server the editor can connect to.

In your `.vimrc`:
```
Plug 'andreypopp/julia-repl-vim'
```
to install the editor plugin.

In editor to connect to the REPL server:
```
:JuliaREPLConnect
```

Now `<leader>e` will eval the current line or the current selection in REPL as
if you typed it directly. The `<C-x><C-o>` omni completion will query REPL for
completions.

## Credits

REPL server code is based on [RemoteREPL.jl] project.

[RemoteREPL.jl]: https://github.com/c42f/RemoteREPL.jl
