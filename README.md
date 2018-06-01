# traces.vim

## Overview
This plugin highlights patterns and ranges for EX commands.

It also provides live preview for the following EX commands:
```
:substite
:smagic
:snomagic
```

## Requirements
### Vim v8.0.1206+
or
### Neovim v0.2.3+
#### Notes for Neovim users

 - this plugin uses recently introduced feature `CmdlineLeave`, please update your Neovim to latest version
 - this plugin is not compatible with [inccommand](https://neovim.io/doc/user/options.html#'inccommand'),
   it will disable itself if inccommand is enabled

## Example
![example](img/traces_example.gif?raw=true)

## Installation
### Linux
`git clone https://github.com/markonm/traces.vim ~/.vim/pack/plugins/start/traces.vim~

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
