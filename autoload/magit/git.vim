let s:git_cmd="GIT_CONFIG=/dev/null GIT_CONFIG_NOSYSTEM=1 git"


function! magit#git#get_version()
	if ( !exists("s:git_version") )
		let s:git_version = matchlist(system(s:git_cmd . " --version"),
		\ 'git version \(\d\+\)\.\(\d\+\)\.\(\d\+\)\.\(\d\+\)\.\(g\x\+\)')[1:5]
	endif
	return s:git_version
endfunction

function! magit#git#is_version_sup_equal(major, minor, rev)
	let git_ver = magit#git#get_version()
	return ( ( a:major > git_ver[0] ) ||
			\ (a:major >= git_ver[0] && a:minor > git_ver[1] ) ||
			\ (a:major >= git_ver[0] && a:minor >= git_ver[1] && a:rev >= git_ver[2] )
			\ )
endfunction

" magit#git#get_status: this function returns the git status output formated
" into a List of Dict as
" [ {staged', 'unstaged', 'filename'}, ... ]
function! magit#git#get_status()
	let file_list = []

	" systemlist v7.4.248 problem again
	" we can't use git status -z here, because system doesn't make the
	" difference between NUL and NL. -status z terminate entries with NUL,
	" instead of NF
	let status_list=magit#utils#systemlist(s:git_cmd . " status --porcelain")
	for file_status_line in status_list
		let line_match = matchlist(file_status_line, '\(.\)\(.\) \%(.\{-\} -> \)\?"\?\(.\{-\}\)"\?$')
		let filename = line_match[3]
		call add(file_list, { 'staged': line_match[1], 'unstaged': line_match[2], 'filename': filename })
	endfor
	return file_list
endfunction

" magit#git#is_work_tree: this function check that path passed as parameter is
" inside a git work tree
" param[in] path: path to check
" return: top work tree path if in a work tree, empty string otherwise
function! magit#git#is_work_tree(path)
	let dir = getcwd()
	try
		call magit#utils#lcd(a:path)
		let top_dir=magit#utils#strip(
					\ system(s:git_cmd . " rev-parse --show-toplevel")) . "/"
		if ( v:shell_error != 0 )
			return ''
		endif
		return top_dir
	finally
		call magit#utils#lcd(dir)
	endtry
endfunction

" magit#git#set_top_dir: this function set b:magit_top_dir and b:magit_git_dir 
" according to a path
" param[in] path: path to set. This path must be in a git repository work tree
function! magit#git#set_top_dir(path)
	let dir = getcwd()
	try
		call magit#utils#lcd(a:path)
		let top_dir=magit#utils#strip(
					\ system(s:git_cmd . " rev-parse --show-toplevel")) . "/"
		if ( v:shell_error != 0 )
			throw "magit: git-show-toplevel error: " . top_dir
		endif
		let git_dir=magit#utils#strip(system(s:git_cmd . " rev-parse --git-dir")) . "/"
		if ( v:shell_error != 0 )
			throw "magit: git-git-dir error: " . git_dir
		endif
		let b:magit_top_dir=top_dir
		let b:magit_git_dir=git_dir
	finally
		call magit#utils#lcd(dir)
	endtry
endfunction

" magit#git#top_dir: return the absolute path of current git worktree for the
" current magit buffer
" return top directory
function! magit#git#top_dir()
	if ( !exists("b:magit_top_dir") )
		throw 'top_dir_not_set'
	endif
	return b:magit_top_dir
endfunction

" magit#git#git_dir: return the absolute path of current git worktree
" return git directory
function! magit#git#git_dir()
	if ( !exists("b:magit_git_dir") )
		throw 'git_dir_not_set'
	endif
	return b:magit_git_dir
endfunction

" magit#git#git_diff: helper function to get diff of a file
" nota: when git fail (due to misformated patch for example), an error
" message is raised.
" param[in] filemane: it must be quoted if it contains spaces
" param[in] status: status of the file (see g:magit_git_status_code)
" param[in] mode: can be staged or unstaged
function! magit#git#git_diff(filename, status, mode)
	let dev_null = ( a:status == '?' ) ? " /dev/null " : " "
	let staged_flag = ( a:mode == 'staged' ) ? " --staged " : " "
	let git_cmd="git diff --no-ext-diff " . staged_flag .
				\ "--no-color --patch -- " . dev_null . " "
				\ .a:filename
	silent let diff_list=magit#utils#systemlist(git_cmd)
	if ( empty(diff_list) )
		echohl WarningMsg
		echom "diff command \"" . git_cmd . "\" returned nothing"
		echohl None
		throw 'diff error'
	endif
	return diff_list
endfunction

" magit#git#sub_check: this function checks if given submodule has modified or
" untracked content
" param[in] submodule: submodule path
" param[in] check_level: can be modified or untracked
function! magit#git#sub_check(submodule, check_level)
	let ignore_flag = ( a:check_level == 'modified' ) ?
				\ '--ignore-submodules=untracked' : ''
	let git_cmd="git status --porcelain " . ignore_flag . " " . a:submodule
	return ( !empty(magit#utils#systemlist(git_cmd)) )
endfunction

" magit#git#git_sub_summary: helper function to get diff of a submodule
" nota: when git fail (due to misformated patch for example), an error
" message is raised.
" param[in] filemane: it must be quoted if it contains spaces
" param[in] mode: can be staged or unstaged
function! magit#git#git_sub_summary(filename, mode)
	let staged_flag = ( a:mode == 'staged' ) ? " --cached " : " --files "
	let git_cmd="git submodule summary " . staged_flag . " HEAD "
				\ .a:filename
	silent let diff_list=magit#utils#systemlist(git_cmd)
	if ( empty(diff_list) )
		if ( a:mode == 'unstaged' )
			if ( magit#git#sub_check(a:filename, 'modified') )
				return "modified content"
			endif
			if ( magit#git#sub_check(a:filename, 'untracked') )
				return "untracked content"
			endif
		endif
		echohl WarningMsg
		echom "diff command \"" . git_cmd . "\" returned nothing"
		echohl None
		throw 'diff error'
	endif
	return diff_list
endfunction

" magit#git#git_add: helper function to add a whole file
" nota: when git fail (due to misformated patch for example), an error
" message is raised.
" param[in] filemane: it must be quoted if it contains spaces
function! magit#git#git_add(filename)
	let git_cmd=s:git_cmd . " add --no-ignore-removal -- " . a:filename
	silent let git_result=magit#utils#system(git_cmd)
	if ( v:shell_error != 0 )
		echoerr "Git error: " . git_result
		echoerr "Git cmd: " . git_cmd
	endif
endfunction

" magit#git#git_checkout: helper function to add a whole file
" nota: when git fail (due to misformated patch for example), an error
" message is raised.
" param[in] filemane: it must be quoted if it contains spaces
function! magit#git#git_checkout(filename)
	let git_cmd=s:git_cmd . " checkout -- " . a:filename
	silent let git_result=magit#utils#system(git_cmd)
	if ( v:shell_error != 0 )
		echoerr "Git error: " . git_result
		echoerr "Git cmd: " . git_cmd
	endif
endfunction

" magit#git#git_reset: helper function to add a whole file
" nota: when git fail (due to misformated patch for example), an error
" message is raised.
" param[in] filemane: it must be quoted if it contains spaces
function! magit#git#git_reset(filename)
	let git_cmd=s:git_cmd . " reset HEAD -- " . a:filename
	silent let git_result=magit#utils#system(git_cmd)
	if ( v:shell_error != 0 )
		echoerr "Git error: " . git_result
		echoerr "Git cmd: " . git_cmd
	endif
endfunction

" magit#git#git_apply: helper function to stage a selection
" nota: when git fail (due to misformated patch for example), an error
" message is raised.
" param[in] selection: the text to stage. It must be a patch, i.e. a diff 
" header plus one or more hunks
" return: no
function! magit#git#git_apply(header, selection)
	let selection = magit#utils#flatten(a:header + a:selection)
	if ( selection[-1] !~ '^$' )
		let selection += [ '' ]
	endif
	let git_cmd=s:git_cmd . " apply --recount --no-index --cached -"
	silent let git_result=magit#utils#system(git_cmd, selection)
	if ( v:shell_error != 0 )
		echoerr "Git error: " . git_result
		echoerr "Git cmd: " . git_cmd
		echoerr "Tried to aply this"
		echoerr string(selection)
	endif
endfunction

" magit#git#git_unapply: helper function to unstage a selection
" nota: when git fail (due to misformated patch for example), an error
" message is raised.
" param[in] selection: the text to stage. It must be a patch, i.e. a diff 
" header plus one or more hunks
" return: no
function! magit#git#git_unapply(header, selection, mode)
	let cached_flag=''
	if ( a:mode == 'staged' )
		let cached_flag=' --cached '
	endif
	let selection = magit#utils#flatten(a:header + a:selection)
	if ( selection[-1] !~ '^$' )
		let selection += [ '' ]
	endif
	silent let git_result=magit#utils#system(
		\ s:git_cmd . " apply --recount --no-index " . cached_flag . " --reverse - ",
		\ selection)
	if ( v:shell_error != 0 )
		echoerr "Git error: " . git_result
		echoerr "Tried to unaply this"
		echoerr string(selection)
	endif
endfunction

" magit#git#submodule_status: return the submodule status output
function! magit#git#submodule_status()
	return system(s:git_cmd . " submodule status")
endfunction

" magit#git#current_branch: return the current branch name, HEAD if not on a
" branch
function! magit#git#current_branch()
	return magit#utils#strip(magit#utils#system(s:git_cmd .
				\ " rev-parse --abbrev-ref HEAD"))
endfunction

" magit#git#last_commit: return the summary of the last commit of the current
" branch
function! magit#git#last_commit()
	return magit#utils#strip(magit#utils#system(s:git_cmd .
				\ " show -s --oneline"))
endfunction

" magit#git#default_remote: return the default remote name of the current
" branch
function! magit#git#default_remote(branch)
	let git_cmd = s:git_cmd .
		\ " for-each-ref --format='%(push:short)' refs/heads/" . a:branch
	let remote = magit#utils#strip(magit#utils#system(git_cmd))
	"WRONG! local branch can be different than remote branch!
	let remote = remote[:-(strlen(a:branch)+2)]
	if ( index(remote, b:remote_names) == -1 )
		echoerr 'Magit internal error in magit#git#default_remote, please report a bug'
	endif
	return remote
endfunction

" magit#git#refresh_remote_list: update the buffer variable b:remote_names
" with remote names
function! magit#git#refresh_remote_list()
	let b:remote_names = magit#utils#systemlist(s:git_cmd . " remote")
endfunction

" magit#git#remote_comp: completion function for remote names
function! magit#git#remote_comp(lead,cmd,pos)
	return filter(copy(b:remote_names), 'v:val =~ "^' .a:lead. '"'  )
endfunction

" magit#git#remote_branch_comp: completion function for remote branch names
function! magit#git#remote_branch_comp(lead,cmd,pos)
	let remote_name = b:cur_push_remote . "/"
	let remote_branches = magit#utils#systemlist(s:git_cmd .
		\ " for-each-ref --format='%(refname:short)' refs/remotes/" .
		\ remote_name)
	let len=strlen(remote_name)
	call map(remote_branches, 'v:val[' . len . ':]')
	call filter(remote_branches, 'v:val =~ "^' .a:lead. '"'  )
	return remote_branches
endfunction

" magit#git#push
function! magit#git#push(remote, branch)
	silent let git_result=magit#utils#system(
		\ s:git_cmd . " push " . a:remote . " " . a:branch )
	if ( v:shell_error != 0 )
		echoerr "Git push error: " . git_result
	endif
endfunction

" remote.pushdefault and branch.<name>.pushremote since 1.8.3
" @{push} since 2.5.0
