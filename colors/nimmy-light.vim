" =============================================================================
" File:         nimmy-light.vim
" Description:  Light-mode pastel retro theme (Eye-friendly for daytime).
" License:      GPL-2.0
" =============================================================================

hi clear
if exists("syntax_on") | syntax reset | endif
let g:colors_name = "nimmy-light"
set background=light

" --- Palette ---
let s:bg0 = "#fbf1c7" " Light cream background
let s:bg1 = "#ebdbb2" " Selection background
let s:fg0 = "#3c3836" " Dark gray text
let s:gray = "#7c6f64" " Soft gray comments

" Inverted & Darkened Pastels
let s:pink   = "#af3a03" 
let s:aqua   = "#427b58"
let s:yellow = "#b57614"
let s:purple = "#8f3f71"
let s:blue   = "#076678"

function! s:hi(group, fg, bg, attr)
  let l:cmd = "hi " . a:group
  if a:fg != "" | let l:cmd .= " guifg=" . a:fg | endif
  if a:bg != "" | let l:cmd .= " guibg=" . a:bg | endif
  if a:attr != "" | let l:cmd .= " gui=" . a:attr | endif
  execute l:cmd
endfunction

" --- UI & Editor ---
call s:hi("Normal", s:fg0, s:bg0, "none")
call s:hi("Comment", s:gray, "", "italic")
call s:hi("LineNr", s:gray, "", "none")
call s:hi("CursorLine", "", s:bg1, "none")
call s:hi("Search", s:bg0, s:yellow, "none")
call s:hi("Visual", "", s:bg1, "none")
call s:hi("Pmenu", s:fg0, s:bg1, "none")
call s:hi("PmenuSel", s:bg0, s:blue, "none")

" --- Syntax (General) ---
call s:hi("Statement", s:pink, "", "bold")
call s:hi("String", s:aqua, "", "none")
call s:hi("Function", s:yellow, "", "none")
call s:hi("Constant", s:purple, "", "none")
call s:hi("Identifier", s:blue, "", "none")
call s:hi("Type", s:blue, "", "none")