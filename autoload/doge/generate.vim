let s:save_cpo = &cpoptions
set cpoptions&vim

""
" @public
" Generates a comment based on a given pattern.
function! doge#generate#pattern(pattern) abort
  " Assuming multiline function expressions won't be longer than 15 lines.
  let l:lines = getline('.', line('.') + 15)

  " Skip if the cursor doesn't start with text.
  if empty(trim(l:lines[0]))
    return 0
  endif

  " Skip immediately if the current line does not match.
  let l:curr_line = escape(trim(join(l:lines, ' ')), '\')
  if l:curr_line !~# a:pattern['match']
    return 0
  endif

  " Extract the primary tokens.
  let l:tokens = doge#token#extract(
        \ l:curr_line,
        \ a:pattern['match'],
        \ a:pattern['match_group_names']
        \ )[0]

  try
    let l:preprocess_fn = printf('doge#preprocessors#%s#tokens', &filetype)
    call function(l:preprocess_fn)(l:tokens)
  catch /E117: Unknown function/
  endtry

  " Split the 'parameters' token value into a list.
  if has_key(a:pattern, 'parameters')
    let l:params_dict = a:pattern['parameters']
    let l:params = l:tokens['parameters']

    " Go through each parameter, match the regex, extract the token values and
    " replace the 'parameters' key with the formatted version.
    let l:formatted_params = []
    let l:param_tokens = doge#token#extract(l:params, l:params_dict['match'], l:params_dict['match_group_names'])

    " Preprocess the extracted parameter tokens.
    try
      let l:preprocess_fn = printf('doge#preprocessors#%s#parameter_tokens', &filetype)
      call function(l:preprocess_fn)(l:param_tokens)
    catch /E117: Unknown function/
    endtry

    for l:param_token in l:param_tokens
      let l:format = doge#token#replace(l:param_token, l:params_dict['format'])
      let l:format = join(filter(l:format, "v:val !=# ''"), ' ')
      if g:doge_comment_todo_suffix == v:false
        let l:format = substitute(l:format, '\m\s*TODO\s*$', '', 'g')
      endif
      call add(l:formatted_params, l:format)
    endfor
    let l:tokens['parameters'] = l:formatted_params
  endif

  " Create the comment by replacing the tokens in the template with their
  " corresponding values.
  let l:comment = []
  for l:line in a:pattern['comment']['template']
    " If empty lines are present, just append them to ensure a whiteline is
    " inserted rather then completely removed. This allows us to insert some
    " whitelines in the comment template.
    if empty(l:line)
      call add(l:comment, l:line)
      continue
    endif

    let l:line_replaced = split(doge#token#replace(l:tokens, l:line), "\n")
    for l:replaced in l:line_replaced
      call add(l:comment, l:replaced)
    endfor
  endfor

  if a:pattern['comment']['insert'] ==# 'below'
    let l:comment_lnum_insert_position = line('.')
    let l:comment_lnum_inherited_indent = line('.') + 1
  else
    let l:comment_lnum_inherited_indent = line('.')
    let l:comment_lnum_insert_position = line('.') - 1
  endif

  " vint: -ProhibitUnusedVariable
  let l:Indent = function('doge#indent#add', [l:comment_lnum_inherited_indent])
  " vint: +ProhibitUnusedVariable

  " Indent the comment.
  let l:comment = map(l:comment, { k, line -> l:Indent(line) })

  try
    let l:preprocess_fn = printf('doge#preprocessors#%s#insert_position', &filetype)
    let l:preprocessed_insert_position = function(l:preprocess_fn)(l:comment_lnum_insert_position)
    let l:comment_lnum_insert_position = l:preprocessed_insert_position
  catch /E117: Unknown function/
  endtry

  " Write the comment.
  call append(l:comment_lnum_insert_position, l:comment)

  " Enable interactive mode.
  if g:doge_comment_interactive == v:true
    if a:pattern['comment']['insert'] ==# 'below'
      let l:todo_match = search('TODO', 'nW', l:comment_lnum_insert_position + len(l:comment))
    else
      let l:todo_match = search('TODO', 'bnW', l:comment_lnum_insert_position + 1)
    endif
    if l:todo_match != 0
      let l:todo_count = doge#helpers#count(
            \ 'TODO',
            \ (l:comment_lnum_insert_position + 1),
            \ (l:comment_lnum_insert_position + 1 + len(l:comment))
            \ )
      if l:todo_count > 0
        let b:doge_interactive = {
              \ 'comment': l:comment,
              \ 'lnum_comment_start_pos': (l:comment_lnum_insert_position + 1),
              \ 'lnum_comment_end_pos': (l:comment_lnum_insert_position + len(l:comment)),
              \ }
        " Go to the top of the comment and select the first TODO.
        exe l:comment_lnum_insert_position + 1
        call search('TODO', 'W')
        execute("normal! viwo\<C-g>")
      endif
    endif
  endif

  " Return 1 to indicate we have succesfully inserted the comment.
  return 1
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
