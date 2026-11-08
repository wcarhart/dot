" prefer vim over vi
set nocompatible

" enable syntax highlighting
syntax on

" automatically detect syntax, plugin, and indentation rules from filetype
filetype plugin indent on

" enable line numbers
set number

" enable cursor position
set ruler

" always show status line
set laststatus=2

" enable autocomplete in command mode
set wildmenu

" enable UTF8 encoding
set encoding=utf-8

" enable intuitive backspace in insert mode
set backspace=indent,eol,start

" use spaces for indentation
set expandtab

" 1 tab = 4 spaces
set shiftwidth=4
set tabstop=4
set softtabstop=4

" enable autoindentation for new lines
set autoindent

" enable highlighting of search results
set hlsearch

" enable incremental search on matching tokens
set incsearch

" ignore case in search queries
set ignorecase

" disable ignorecase if search query contains uppercase letters
set smartcase

" clear search highlights with ENTER
nnoremap <silent> <CR> :nohlsearch<CR><CR>

" enable clipboard sharing with system clipboard (like for yank, paste, etc.)
set clipboard=unnamedplus

" restore cursor position after file is opened
autocmd BufReadPost *
  \ if line("'\"") > 0 && line("'\"") <= line("$") |
  \   execute "normal! g'\"" |
  \ endif
