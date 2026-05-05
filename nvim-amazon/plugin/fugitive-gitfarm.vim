" https://w.amazon.com/bin/view/Users/Ethdestr/vim/#HFugitiveintegrationwithCodeBrowser

" ============================================================================
" File:        fugitive-gitfarm.vim
" Maintainer:  Benoît Taine <btaine@amazon.com>
" ============================================================================

function! s:function(name) abort
  return function(substitute(a:name,'^s:',matchstr(expand('<sfile>'), '<SNR>\d\+_'),''))
endfunction

function! s:gitfarm_url(opts) abort
  if a:0 || type(a:opts) != type({})
    return ''
  endif
  let default_domain = 'git\.amazon\.com'
  let domain = exists('g:fugitive_gitfarm_domain') ? g:fugitive_gitfarm_domain : default_domain
  let repo = matchstr(get(a:opts, 'remote'), '^ssh://\(\w\+@\)\?' . domain . '\(:\d\+\)\?/pkg/[[:alnum:]_.-]\+$')
  if repo ==# ''
    return ''
  endif
  let package = split(repo, '/')[4]
  let path = substitute(a:opts.path, '^/', '', '')
  let root = 'https://code.amazon.com/packages/' . package
  if path =~# '^\.git/\%(config$\|hooks\>\)'
    return root . '/repo-info'
  elseif path =~# '^\.git\>'
    return root
  endif
  if a:opts.commit =~# '^\d\=$'
    let commit = a:opts.repo.rev_parse('HEAD')
  else
    let commit = a:opts.commit
  endif
  if get(a:opts, 'type', '') ==# 'tree' || a:opts.path =~# '/$'
    let url = substitute(root . '/trees/' . commit . '/--/' . path, '/$', '', 'g')
  elseif get(a:opts, 'type', '') ==# 'blob' || a:opts.path =~# '[^/]$'
    let url = root . '/blobs/' . commit . '/--/' . path
    if get(a:opts, 'line2')
      let url .= '#L' . a:opts.line1
      " Linking a range of lines
      if a:opts.line1 != a:opts.line2
        let url .= '-L' . a:opts.line2
      endif
    endif
  else
    let url = root . '/commits/' . commit
  endif
  return url
endfunction

if !exists('g:fugitive_browse_handlers')
  let g:fugitive_browse_handlers = []
endif

call insert (g:fugitive_browse_handlers, s:function('s:gitfarm_url'))
