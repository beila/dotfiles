let g:airline_powerline_fonts = 1
let g:airline_theme='deus'
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#tab_nr_type = 1
" `tail` (basename only) is much faster than `unique_tail` on tab switches —
" the latter recomputes shortest-unique-suffix across every buffer in the
" current tab on each TabEnter (O(buffers × path-components)) and noticeably
" lags with many open buffers. Trade-off: same-named files in different
" directories collide in the display. Switch back to `unique_tail` if that
" matters.
let g:airline#extensions#tabline#formatter = 'tail'
