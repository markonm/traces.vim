# traces.vim

## Overview
This plugin will highlight patterns and ranges for EX commands.

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

## How to install?
[Tutorial](https://gist.github.com/manasthakur/ab4cf8d32a28ea38271ac0d07373bb53)

## Inspiration
 - [vim-over](https://github.com/osyo-manga/vim-over)
 - [incsearch.vim](https://github.com/haya14busa/incsearch.vim)
 - [inccommand](https://neovim.io/doc/user/options.html#'inccommand')
