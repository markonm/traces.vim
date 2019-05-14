# traces.vim

## Overview
This plugin highlights patterns and ranges for Ex commands in Command-line mode.

It also provides live preview for the following Ex commands:
```
:substitute
:smagic
:snomagic
```

## Requirements
### Vim v8.0.1206+
or
### Neovim v0.2.3+
 - this plugin is not compatible with [inccommand](https://neovim.io/doc/user/options.html#'inccommand'), please turn it off if you want to use this plugin


**Note**: some of the features provided by this plugin are already present in Vim/Neovim.

|                                                    | traces.vim  | Vim*  | Neovim |
| ---------------------------------------------      | :---------: | :---: | :---:  |
| `:substitute` preview                              | ✓           |       | ✓      |
| pattern preview for `:substitute`                  | ✓           | ✓     | ✓      |
| pattern preview for `:global`, `:vglobal`, `:sort` | ✓           | ✓     |        |
| pattern preview for `:vimgrep`                     |             | ✓     |        |
| range preview                                      | ✓           |       |        |
| partial off-screen results in a preview window     |             |       | ✓      |

\* added by patch [v8.1.0271](https://github.com/vim/vim/commit/b0acacd767a2b0618a7f3c08087708f4329580d0)

## Example
![example](img/traces_example.gif?raw=true)

## Installation
### Linux
`git clone https://github.com/markonm/traces.vim ~/.vim/pack/plugins/start/traces.vim`

Run the `:helptags` command to generate the doc/tags file.

`:helptags ~/.vim/pack/plugins/start/traces.vim/doc`

### Windows
`git clone https://github.com/markonm/traces.vim %HOMEPATH%/vimfiles/pack/plugins/start/traces.vim`

Run the `:helptags` command to generate the doc/tags file.

`:helptags ~/vimfiles/pack/plugins/start/traces.vim/doc`

## Inspiration
 - [vim-over](https://github.com/osyo-manga/vim-over)
 - [incsearch.vim](https://github.com/haya14busa/incsearch.vim)
 - [inccommand](https://neovim.io/doc/user/options.html#'inccommand')
