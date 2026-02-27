" Disable clipboard monitoring to prevent flickering in neovide
let g:yankring_clipboard_monitor = 0

" http://stevelosh.com/blog/2010/09/coming-home-to-vim/#yankring
nnoremap <silent> <F3> :YRShow<cr>
inoremap <silent> <F3> <ESC>:YRShow<cr>

