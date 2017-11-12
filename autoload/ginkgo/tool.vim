function! ginkgo#tool#ParseErrors(lines) abort 
	let errors = []
	let reporting_sections = s:parse_reporting_sections(a:lines)

	for reporting_section in reporting_sections
		let errors = errors + s:get_errors(reporting_section) 
	endfor 

	return errors 
endfunction 

" get_errors gets a list of errors from a reporting_section. Each 
" reporting section should only represent one error, but we return 
" multiple lines of errors for the extra text from that section.
function! s:get_errors(reporting_section) abort 
	let errors = []

	let indentation_levels = s:split_indentation_levels(a:reporting_section)
	let error_fileloc = matchlist(indentation_levels[-1][-1], '\(.*\):\(.*\)')

	let error_txts = []
	for indentation_level in indentation_levels 
		call add(error_txts, indentation_level[0])
	endfor 

	call add(errors, {
            \ "filename" : fnamemodify(error_fileloc[1], ':p'),
            \ "lnum"     : error_fileloc[2],
            \ "text"     : join(error_txts, ' -> '),
            \ })

	for line in indentation_levels[-1][2:-2]
		call add(errors, {"text": "   " . line})
	endfor 

	return errors 
endfunction 

" split_indentation_levels goes through each line in a reporting 
" section and separates them based on how much whitespace they have. 
" The max whitespace is determined by the very last line. 
" Returns a list indentation levels, containing a list of lines for 
" that level.
function! s:split_indentation_levels(reporting_section) abort 
	let indentation_levels = [] 
	let indentation_level = [] 
	let current_whitespace = 0 

	let max_whitespace = s:get_whitespace(a:reporting_section[-1])

	for line in a:reporting_section
		let line_whitespace = s:get_whitespace(line)

		if line_whitespace > max_whitespace 
			let line_whitespace = max_whitespace 
		endif 

		if line_whitespace != current_whitespace 
			let current_whitespace = line_whitespace

			call add(indentation_levels, indentation_level)
			let indentation_level = []
		endif 

		call add(indentation_level, line[line_whitespace:])
	endfor 

	call add(indentation_levels, indentation_level)
	return indentation_levels
endfunction 

function! s:get_whitespace(line) abort 
	return match(a:line, '\S')
endfunction 

" parse_reporting_sections looks through each line of the ginkgo output 
" and looks for blocks of text following a series of dashes. If the 
" first line says Failure, the rest of the block before the next 
" series of dashes will be added as a reporting section.
" Return a list of these sections, where each section is 
" an array of lines 
function! s:parse_reporting_sections(lines) abort 
	let reporting_sections = [] 
	let reporting_section = [] 
	let parsing_reporting_section = 0  
	let found_dashes = 0 

	for line in a:lines 
		if !len(line)
			continue 
		elseif match(line, '^--\+$') >= 0 
			let found_dashes = 1 

			if parsing_reporting_section
				" Done parsing reporting section 
				call add(reporting_sections, reporting_section) 
				let reporting_section = [] 
				let parsing_reporting_section = 0
			endif 

			continue 
		elseif !found_dashes 
			continue 
		endif 

		if !parsing_reporting_section
			" We're the line right after the dashes. Check to 
			" see if this line represents a reporting section start. 
			if match(line, 'Failure\s') >= 0 
				let reporting_section = []
				let parsing_reporting_section = 1 
			else 
				let found_dashes = 0 
			endif 

			continue 
		endif 

		call add(reporting_section, line)
	endfor 

	return reporting_sections 
endfunction 
