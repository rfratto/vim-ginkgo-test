" Test runs `ginkgo` in the current directory. Every argument is appended to 
" the final ginkgo command. This function is essentially a clone of 
" go#test#Test minus the compile argument and runs ginkgo instead.
function! ginkgo#test#Test(bang, ...) abort 
	let args = ["-noColor"]

	if exists('g:go_build_tags')
		let tags = get(g:, 'go_build_tags')
		call extend(args, ["-tags", tags])
	endif 

	if a:0 
		let goargs = a:000

		" Do not expand for coverage mode as we're passing the arg ourselves 
		if a:1 !=# '-coverprofile'
			" Expand all wildcards(i.e., '%' to the current file name)
			let goargs = map(copy(a:000), "expand(v:val)")
		endif 

		if !(has('nvim') || go#util#has_job())
			let goargs = go#util#Shelllist(goargs, 1)
		endif 

		call extend(args, goargs, 1)
	else 
		" Only add this if no custom flags are passed 
		let timeout = get(g:, 'go_test_timeout', '10s')
		call add(args, printf("-timeout=%s", timeout))
	endif 

	if get(g:, 'go_echo_command_info', 1)
		call ginkgo#util#EchoProgress("Testing Ginkgo...")
	endif

	if go#util#has_job() 
		" Use vim's job functionality to call it asynchronously 
		let job_args = {
			\	'cmd': ['ginkgo'] + args,
			\ 'bang': a:bang,
			\ 'winnr': winnr(),
			\ 'dir': getcwd(),
			\ 'jobdir': fnameescape(expand('%:p:h')),
			\ }

		call s:test_job(job_args)
		return 
	elseif has('nvim')
		" Use nvim's job functionality 
		if get(g:, 'go_term_enabled', 0)
			let id = ginkgo#term#new(a:bang, ["ginkgo"] + args)
		else 
			let id = ginkgo#jobcontrol#Spawn(a:bang, "test", "GoTest", args)
		endif 

		return id 
	endif 

	call go#cmd#autowrite()
	redraw 

	let command = "ginkgo " . join(args, ' ')
	let out = go#tool#ExecuteInDir(command)

	let l:listtype = go#list#Type("GoTest")

	let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd ' : 'cd '
	let dir = getcwd() 
	execute cd fnameescape(expand('%:p:h'))

	if go#util#ShellError() != 0 
		let errors = ginkgo#tool#ParseErrors(split(out, '\n'))
		let errors = go#tool#FilterValids(errors)

		call go#list#Populate(l:listtype, errors, command)
		call go#list#Window(l:listtype, len(errors))

		if !empty(errors) && !a:bang 
			call go#list#JumpToFirst(l:listtype)
		elseif empty(errors)
			" Failed to parse errors, output the original content
			call ginkgo#util#EchoError(out)
		endif 

		call ginkgo#util#EchoError("[GinkgoTest] FAIL")
	else 
		call go#list#Clean(l:listtype)
		call go#list#Window(l:listtype)

		call ginkgo#util#EchoSuccess("[GinkgoTest] PASS")
	endif 

	execute cd . fnameescape(dir)
endfunction 


function! s:test_job(args) abort 
	let status_dir = expand('%:p:h')
	let started_at = reltime()

	let status = {
				\ 'desc': 'current status',
				\ 'type': 'test',
				\ 'state': 'started',
				\ }

	call go#statusline#Update(status_dir, status)
	call go#cmd#autowrite()

	let messages = []
	function! s:callback(chan, msg) closure 
		call add(messages, a:msg) 
	endfunction 
	
	function! s:exit_cb(job, exitval) closure 
		let status = {
					\ 'desc': 'current status',
					\ 'type': 'test',
					\ 'state': 'pass'
					\ }

		if a:exitval 
			let status.state = "failed"
		endif 

		if get(g:, 'go_echo_command_info', 1)
			if a:exitval == 0
				call ginkgo#util#EchoSuccess("[GinkgoTest] PASS")
			else 
				call ginkgo#util#EchoError("[GinkgoTest] FAIL")
			endif 
		endif 

		let elapsed_time = reltimestr(reltime(started_at))
		let elapsed_time = substitute(elapsed_time, '^\s*\(.\{-}\)\s*$', '\1', '')
		let status.state .= printf(" (%ss)", elapsed_time)

		call go#statusline#Update(status_dir, status)

		if a:exitval == 0
			let l:listtype = go#list#Type("GoTest")

			call go#list#Clean(l:listtype)
			call go#list#Window(l:listtype)

			return
		endif 

		call s:show_errors(a:args, a:exitval, messages)
	endfunction 

	let start_options = {
				\ 'callback': funcref("s:callback"),
				\ 'exit_cb': funcref("s:exit_cb"),
				\}

	" Modify GOPATH if needed 
	let old_gopath = $GOPATH 
	let $GOPATH = go#path#Detect()

	" Prestart 
	let dir = getcwd()
	let cd = exists('*haslocaldir*') && haslocaldir() ? 'lcd ' : 'cd '
	let jobdir = fnameescape(expand("%:p:h"))
	execute cd . jobdir 

	call job_start(a:args.cmd, start_options)

	" Poststart 
	execute cd . fnameescape(dir)
	let $GOPATH = old_gopath
endfunction

" show_errors parses the given list of lines of a 'ginkgo' output 
" and returns a quickfix compatible list of errors. It's intended 
" to be used only for ginkgo test output.
function! s:show_errors(args, exit_val, messages) abort 
	let l:listtype = go#list#Type("GoTest")

	let cd = exists('*haslocaldir*') && haslocaldir() ? 'lcd ' : 'cd '
	try 
		execute cd a:args.jobdir 
		let errors = ginkgo#tool#ParseErrors(a:messages)
		let errors = go#tool#FilterValids(errors)
	finally 
		execute cd . fnameescape(a:args.dir)
	endtry 

	if !len(errors)
		" Failed to parse errors, output the original content
		call ginkgo#util#EchoError(a:messages)
		call ginkgo#util#EchoError(a:args.dir)
		
		return 
	endif 

	if a:args.winnr == winnr()
		call go#list#Populate(l:listtype, errors, join(a:args.cmd))
		call go#list#Window(l:listtype, len(errors))

		if !empty(errors) && !a:args.bang 
			call go#list#JumpToFirst(l:listtype)
		endif 
	endif 
endfunction
