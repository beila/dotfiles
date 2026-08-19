let g:airline_powerline_fonts = 1
let g:airline_theme='deus'
let g:airline#extensions#branch#enabled = 0

function! JjWorkspaceStatus() abort
    return get(w:, 'jj_workspace', '')
endfunction

function! s:AirlineJjWorkspace() abort
    call airline#parts#define_function('jj_workspace', 'JjWorkspaceStatus')
    let g:airline_section_b = airline#section#create_left(['hunks', 'jj_workspace'])
endfunction

let g:airline_filetype_overrides = get(g:, 'airline_filetype_overrides', {})
let g:airline_filetype_overrides.fugitive = ['fugitive', '%{JjWorkspaceStatus()}']

augroup airline_jj_workspace
    autocmd!
    autocmd User AirlineAfterInit call <SID>AirlineJjWorkspace()
augroup END

" Tabline off: `tail` formatter removed upstream; `unique_tail` lags with
" many buffers.
let g:airline#extensions#tabline#enabled = 0
