[Collater::] The Collater.

To collate material generated by the weaver into finished, fully-woven files.

@h Collation.
This is the process of reading a template file, substituting material into
placeholders in it, and writing the result.

The collater needs to operate as a little processor interpreting a
meta-language all of its very own, with a stack for holding nested repeat
loops, and a program counter and -- well, and nothing else to speak of, in
fact, except for the slightly unusual way that loop variables provide context
by changing the subject of what is discussed rather than by being accessed
directly.

For convenience, we provide three ways to call:

=
void Collater::for_web_and_pattern(text_stream *OUT, web *W,
	weave_pattern *pattern, filename *F, filename *into) {
	Collater::collate(OUT, W, I"", F, pattern, NULL, NULL, NULL, into);
}

void Collater::for_order(text_stream *OUT, weave_order *wv,
	filename *F, filename *into) {
	Collater::collate(OUT, wv->weave_web, wv->weave_range, F, wv->pattern,
		wv->navigation, wv->breadcrumbs, wv, into);
}

void Collater::collate(text_stream *OUT, web *W, text_stream *range,
	filename *template_filename, weave_pattern *pattern, filename *nav_file,
	linked_list *crumbs, weave_order *wv, filename *into) {
	collater_state actual_ies =
		Collater::initial_state(W, range, template_filename, pattern, 
			nav_file, crumbs, wv, into);
	collater_state *ies = &actual_ies;
	Collater::process(OUT, ies);
}

@ The current state of the processor is recorded in the following.

@d TRACE_COLLATER_EXECUTION FALSE /* set true for debugging */

@d MAX_TEMPLATE_LINES 8192 /* maximum number of lines in template */
@d CI_STACK_CAPACITY 8 /* maximum recursion of chapter/section iteration */

=
typedef struct collater_state {
	struct web *for_web;
	struct text_stream *tlines[MAX_TEMPLATE_LINES];
	int no_tlines;
	int repeat_stack_level[CI_STACK_CAPACITY];
	struct linked_list_item *repeat_stack_variable[CI_STACK_CAPACITY];
	struct linked_list_item *repeat_stack_threshold[CI_STACK_CAPACITY];
	int repeat_stack_startpos[CI_STACK_CAPACITY];
	int sp; /* And this is our stack pointer for tracking of loops */
	struct text_stream *restrict_to_range;
	struct weave_pattern *nav_pattern;
	struct filename *nav_file;
	struct linked_list *crumbs;
	int inside_navigation_submenu;
	struct filename *errors_at;
	struct weave_order *wv;
	struct filename *into_file;
	struct linked_list *modules; /* of |module| */
} collater_state;

@ Note the unfortunate maximum size limit on the template file. It means
that really humungous Javascript files in plugins might have trouble, though
if so, they can always be subdivided.

=
collater_state Collater::initial_state(web *W, text_stream *range,
	filename *template_filename, weave_pattern *pattern, filename *nav_file,
	linked_list *crumbs, weave_order *wv, filename *into) {
	collater_state cls;
	cls.no_tlines = 0;
	cls.restrict_to_range = Str::duplicate(range);
	cls.sp = 0;
	cls.inside_navigation_submenu = FALSE;
	cls.for_web = W;
	cls.nav_pattern = pattern;
	cls.nav_file = nav_file;
	cls.crumbs = crumbs;
	cls.errors_at = template_filename;
	cls.wv = wv;
	cls.into_file = into;
	cls.modules = NEW_LINKED_LIST(module);
	if (W) {
		int c = LinkedLists::len(W->md->as_module->dependencies);
		if (c > 0) @<Form the list of imported modules@>;
	}
	@<Read in the source file containing the contents page template@>;
	return cls;
}

@<Form the list of imported modules@> =
	module **module_array = 
		Memory::calloc(c, sizeof(module *), ARRAY_SORTING_MREASON);
	module *M; int d=0;
	LOOP_OVER_LINKED_LIST(M, module, W->md->as_module->dependencies)
		module_array[d++] = M;
	Collater::sort_web(W);
	qsort(module_array, (size_t) c, sizeof(module *), Collater::sort_comparison);
	for (int d=0; d<c; d++) ADD_TO_LINKED_LIST(module_array[d], module, cls.modules);
	Memory::I7_free(module_array, ARRAY_SORTING_MREASON, c*((int) sizeof(module *)));

@<Read in the source file containing the contents page template@> =
	TextFiles::read(template_filename, FALSE,
		"can't find contents template", TRUE, Collater::temp_line, NULL, &cls);
	if (TRACE_COLLATER_EXECUTION)
		PRINT("Read template <%f>: %d line(s)\n", template_filename, cls.no_tlines);
	if (cls.no_tlines >= MAX_TEMPLATE_LINES)
		PRINT("Warning: template <%f> truncated after %d line(s)\n",
			template_filename, cls.no_tlines);

@ =
void Collater::temp_line(text_stream *line, text_file_position *tfp, void *v_ies) {
	collater_state *cls = (collater_state *) v_ies;
	if (cls->no_tlines < MAX_TEMPLATE_LINES)
		cls->tlines[cls->no_tlines++] = Str::duplicate(line);
}

@ Running the engine...

=
void Collater::process(text_stream *OUT, collater_state *cls) {
	int lpos = 0; /* This is our program counter: a line number in the template */
	while (lpos < cls->no_tlines) {
		match_results mr = Regexp::create_mr();
		TEMPORARY_TEXT(tl);
		Str::copy(tl, cls->tlines[lpos++]); /* Fetch the line at the program counter and advance */
		@<Make any necessary substitutions to turn tl into final output@>;
		WRITE("%S\n", tl); /* Copy the now finished line to the output */
		DISCARD_TEXT(tl);
		CYCLE: ;
		Regexp::dispose_of(&mr);
	}
	if (cls->inside_navigation_submenu) WRITE("</ul>");
	cls->inside_navigation_submenu = FALSE;
}

@<Make any necessary substitutions to turn tl into final output@> =
	if (Regexp::match(&mr, tl, L"(%c*?) ")) Str::copy(tl, mr.exp[0]); /* Strip trailing spaces */
	if (TRACE_COLLATER_EXECUTION)
		@<Print line and contents of repeat stack@>;
	if ((Regexp::match(&mr, tl, L"%[%[(%c+)%]%]")) ||
		(Regexp::match(&mr, tl, L" %[%[(%c+)%]%]"))) {
		TEMPORARY_TEXT(command);
		Str::copy(command, mr.exp[0]);
		@<Deal with a Select command@>;
		@<Deal with an If command@>;
		@<Deal with an Else command@>;
		@<Deal with a Repeat command@>;
		@<Deal with a Repeat End command@>;
		DISCARD_TEXT(command);
	}
	@<Skip line if inside a failed conditional@>;
	@<Skip line if inside an empty loop@>;
	@<Make substitutions of square-bracketed variables in line@>;

@h The repeat stack and loops.
This is used only for debugging:

@<Print line and contents of repeat stack@> =
	PRINT("%04d: %S\nStack:", lpos-1, tl);
	for (int j=0; j<cls->sp; j++) {
		if (cls->repeat_stack_level[j] == CHAPTER_LEVEL)
			PRINT(" %d: %S/%S",
				j, ((chapter *)
					CONTENT_IN_ITEM(cls->repeat_stack_variable[j], chapter))->md->ch_range,
				((chapter *)
					CONTENT_IN_ITEM(cls->repeat_stack_threshold[j], chapter))->md->ch_range);
		else if (cls->repeat_stack_level[j] == SECTION_LEVEL)
			PRINT(" %d: %S/%S",
				j, ((section *)
					CONTENT_IN_ITEM(cls->repeat_stack_variable[j], section))->md->sect_range,
				((section *)
					CONTENT_IN_ITEM(cls->repeat_stack_threshold[j], section))->md->sect_range);
	}
	PRINT("\n");

@ We start the direct commands with Select, which is implemented as a
one-iteration loop in which the loop variable has the given section or
chapter as its value during the sole iteration.

@<Deal with a Select command@> =
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, command, L"Select (%c*)")) {
		chapter *C;
		section *S;
		LOOP_OVER_LINKED_LIST(C, chapter, cls->for_web->chapters)
			LOOP_OVER_LINKED_LIST(S, section, C->sections)
				if (Str::eq(S->md->sect_range, mr.exp[0])) {
					Collater::start_CI_loop(cls, SECTION_LEVEL, S_item, S_item, lpos);
					Regexp::dispose_of(&mr);
					goto CYCLE;
				}
		LOOP_OVER_LINKED_LIST(C, chapter, cls->for_web->chapters)
			if (Str::eq(C->md->ch_range, mr.exp[0])) {
				Collater::start_CI_loop(cls, CHAPTER_LEVEL, C_item, C_item, lpos);
				Regexp::dispose_of(&mr);
				goto CYCLE;
			}
		Errors::at_position("don't recognise the chapter or section abbreviation range",
			cls->errors_at, lpos);
		Regexp::dispose_of(&mr);
		goto CYCLE;
	}

@ Conditionals:

@<Deal with an If command@> =
	if (Regexp::match(&mr, command, L"If (%c*)")) {
		text_stream *condition = mr.exp[0];
		int level = IF_FALSE_LEVEL;
		if (Str::eq(condition, I"Chapters")) {
			if (cls->for_web->md->chaptered) level = IF_TRUE_LEVEL;
		} else if (Str::eq(condition, I"Modules")) {
			if (LinkedLists::len(cls->modules) > 0)
				level = IF_TRUE_LEVEL;
		} else if (Str::eq(condition, I"Module Page")) {
			module *M = CONTENT_IN_ITEM(
				Collater::heading_topmost_on_stack(cls, MODULE_LEVEL), module);
			if ((M) && (Colonies::find(M->module_name)))
				level = IF_TRUE_LEVEL;
		} else if (Str::eq(condition, I"Module Purpose")) {
			module *M = CONTENT_IN_ITEM(
				Collater::heading_topmost_on_stack(cls, MODULE_LEVEL), module);
			if (M) {
				TEMPORARY_TEXT(url);
				TEMPORARY_TEXT(purpose);
				WRITE_TO(url, "%p", M->module_location);
				Readme::write_var(purpose, url, I"Purpose");
				if (Str::len(purpose) > 0) level = IF_TRUE_LEVEL;
				DISCARD_TEXT(url);		
				DISCARD_TEXT(purpose);		
			}
		} else if (Str::eq(condition, I"Chapter Purpose")) {
			chapter *C = CONTENT_IN_ITEM(
				Collater::heading_topmost_on_stack(cls, CHAPTER_LEVEL), chapter);
			if ((C) && (Str::len(C->md->rubric) > 0)) level = IF_TRUE_LEVEL;
		} else if (Str::eq(condition, I"Section Purpose")) {
			section *S = CONTENT_IN_ITEM(
				Collater::heading_topmost_on_stack(cls, SECTION_LEVEL), section);
			if ((S) && (Str::len(S->sect_purpose) > 0)) level = IF_TRUE_LEVEL;
		} else {
			Errors::at_position("don't recognise the condition",
				cls->errors_at, lpos);
		}
		Collater::start_CI_loop(cls, level, NULL, NULL, lpos);
		Regexp::dispose_of(&mr);
		goto CYCLE;
	}

@<Deal with an Else command@> =
	if (Regexp::match(&mr, command, L"Else")) {
		if (cls->sp <= 0) {
			Errors::at_position("Else without If",
				cls->errors_at, lpos);
			goto CYCLE;
		}
		switch (cls->repeat_stack_level[cls->sp-1]) {
			case SECTION_LEVEL:
			case CHAPTER_LEVEL:
				Errors::at_position("Else not matched with If",
					cls->errors_at, lpos);
				break;
			case IF_TRUE_LEVEL: cls->repeat_stack_level[cls->sp-1] = IF_FALSE_LEVEL; break;
			case IF_FALSE_LEVEL: cls->repeat_stack_level[cls->sp-1] = IF_TRUE_LEVEL; break;
		}
		Regexp::dispose_of(&mr);
		goto CYCLE;
	}

@ Next, a genuine loop beginning:

@<Deal with a Repeat command@> =
	int loop_level = 0;
	if (Regexp::match(&mr, command, L"Repeat Module")) loop_level = MODULE_LEVEL;
	if (Regexp::match(&mr, command, L"Repeat Chapter")) loop_level = CHAPTER_LEVEL;
	if (Regexp::match(&mr, command, L"Repeat Section")) loop_level = SECTION_LEVEL;
	if (loop_level != 0) {
		linked_list_item *from = NULL, *to = NULL;
		linked_list_item *CI = FIRST_ITEM_IN_LINKED_LIST(chapter, cls->for_web->chapters);
		while ((CI) && (CONTENT_IN_ITEM(CI, chapter)->md->imported))
			CI = NEXT_ITEM_IN_LINKED_LIST(CI, chapter);
		if (loop_level == MODULE_LEVEL) @<Begin a module repeat@>;
		if (loop_level == CHAPTER_LEVEL) @<Begin a chapter repeat@>;
		if (loop_level == SECTION_LEVEL) @<Begin a section repeat@>;
		Collater::start_CI_loop(cls, loop_level, from, to, lpos);
		goto CYCLE;
	}

@<Begin a module repeat@> =
	from = FIRST_ITEM_IN_LINKED_LIST(module, cls->modules);
	to = LAST_ITEM_IN_LINKED_LIST(module, cls->modules);

@<Begin a chapter repeat@> =
	from = CI;
	to = LAST_ITEM_IN_LINKED_LIST(chapter, cls->for_web->chapters);
	if (Str::eq_wide_string(cls->restrict_to_range, L"0") == FALSE) {
		chapter *C;
		LOOP_OVER_LINKED_LIST(C, chapter, cls->for_web->chapters)
			if (Str::eq(C->md->ch_range, cls->restrict_to_range)) {
				from = C_item; to = from;
				break;
			}
	}

@<Begin a section repeat@> =
	chapter *within_chapter =
		CONTENT_IN_ITEM(Collater::heading_topmost_on_stack(cls, CHAPTER_LEVEL),
			chapter);
	if (within_chapter == NULL) {
		if (CI) {
			chapter *C = CONTENT_IN_ITEM(CI, chapter);
			from = FIRST_ITEM_IN_LINKED_LIST(section, C->sections);
		}
		chapter *LC = LAST_IN_LINKED_LIST(chapter, cls->for_web->chapters);
		if (LC) to = LAST_ITEM_IN_LINKED_LIST(section, LC->sections);
	} else {
		from = FIRST_ITEM_IN_LINKED_LIST(section, within_chapter->sections);
		to = LAST_ITEM_IN_LINKED_LIST(section, within_chapter->sections);
	}

@ And at the other bookend:

@<Deal with a Repeat End command@> =
	int end_form = -1;
	if (Regexp::match(&mr, command, L"End Repeat")) end_form = 1;
	if (Regexp::match(&mr, command, L"End Select")) end_form = 2;
	if (Regexp::match(&mr, command, L"End If")) end_form = 3;
	if (end_form > 0) {
		if (cls->sp <= 0) {
			Errors::at_position("stack underflow on contents template",
				cls->errors_at, lpos);
			goto CYCLE;
		}
		switch (cls->repeat_stack_level[cls->sp-1]) {
			case MODULE_LEVEL:
			case CHAPTER_LEVEL:
			case SECTION_LEVEL:
				if (end_form == 3) {
					Errors::at_position("End If not matched with If",
						cls->errors_at, lpos);
					goto CYCLE;
				}
				break;
			case IF_TRUE_LEVEL:
			case IF_FALSE_LEVEL:
				if (end_form != 3) {
					Errors::at_position("If not matched with End If",
						cls->errors_at, lpos);
					goto CYCLE;
				}
				break;
		}
		switch (cls->repeat_stack_level[cls->sp-1]) {
			case MODULE_LEVEL: @<End a module repeat@>; break;
			case CHAPTER_LEVEL: @<End a chapter repeat@>; break;
			case SECTION_LEVEL: @<End a section repeat@>; break;
			case IF_TRUE_LEVEL: @<End an If@>; break;
			case IF_FALSE_LEVEL: @<End an If@>; break;
		}
		goto CYCLE;
	}

@<End a module repeat@> =
	linked_list_item *CI = cls->repeat_stack_variable[cls->sp-1];
	if (CI == cls->repeat_stack_threshold[cls->sp-1])
		Collater::end_CI_loop(cls);
	else {
		cls->repeat_stack_variable[cls->sp-1] =
			NEXT_ITEM_IN_LINKED_LIST(CI, chapter);
		lpos = cls->repeat_stack_startpos[cls->sp-1]; /* Back round loop */
	}

@<End a chapter repeat@> =
	linked_list_item *CI = cls->repeat_stack_variable[cls->sp-1];
	if (CI == cls->repeat_stack_threshold[cls->sp-1])
		Collater::end_CI_loop(cls);
	else {
		cls->repeat_stack_variable[cls->sp-1] =
			NEXT_ITEM_IN_LINKED_LIST(CI, chapter);
		lpos = cls->repeat_stack_startpos[cls->sp-1]; /* Back round loop */
	}

@<End a section repeat@> =
	linked_list_item *SI = cls->repeat_stack_variable[cls->sp-1];
	if ((SI == cls->repeat_stack_threshold[cls->sp-1]) ||
		(NEXT_ITEM_IN_LINKED_LIST(SI, section) == NULL))
		Collater::end_CI_loop(cls);
	else {
		cls->repeat_stack_variable[cls->sp-1] =
			NEXT_ITEM_IN_LINKED_LIST(SI, section);
		lpos = cls->repeat_stack_startpos[cls->sp-1]; /* Back round loop */
	}

@<End an If@> =
	Collater::end_CI_loop(cls);

@ It can happen that a section loop, at least, is empty:

@<Skip line if inside an empty loop@> =
	for (int rstl = cls->sp-1; rstl >= 0; rstl--)
		if (cls->repeat_stack_level[cls->sp-1] == SECTION_LEVEL) {
			linked_list_item *SI = cls->repeat_stack_threshold[cls->sp-1];
			if (NEXT_ITEM_IN_LINKED_LIST(SI, section) ==
				cls->repeat_stack_variable[cls->sp-1])
				goto CYCLE;
		}

@<Skip line if inside a failed conditional@> =
	for (int j=cls->sp-1; j>=0; j--)
		if (cls->repeat_stack_level[j] == IF_FALSE_LEVEL)
			goto CYCLE;

@ If called with the non-conditional levels, the following function returns
the topmost item. It's never called for |IF_TRUE_LEVEL| or |IF_FALSE_LEVEL|.

=
linked_list_item *Collater::heading_topmost_on_stack(collater_state *cls, int level) {
	for (int rstl = cls->sp-1; rstl >= 0; rstl--)
		if (cls->repeat_stack_level[rstl] == level)
			return cls->repeat_stack_variable[rstl];
	return NULL;
}

@ This is the function for starting a loop or code block, which stacks up the
details, and similarly for ending it by popping them again:

@d MODULE_LEVEL 1
@d CHAPTER_LEVEL 2
@d SECTION_LEVEL 3
@d IF_TRUE_LEVEL 4
@d IF_FALSE_LEVEL 5

=
void Collater::start_CI_loop(collater_state *cls, int level,
	linked_list_item *from, linked_list_item *to, int pos) {
	if (cls->sp < CI_STACK_CAPACITY) {
		cls->repeat_stack_level[cls->sp] = level;
		cls->repeat_stack_variable[cls->sp] = from;
		cls->repeat_stack_threshold[cls->sp] = to;
		cls->repeat_stack_startpos[cls->sp++] = pos;
	}
}

void Collater::end_CI_loop(collater_state *cls) {
	cls->sp--;
}

@h Variable substitutions.
We can now forget about this tiny stack machine: the one task left is to
take a line from the template, and make substitutions of variables into
its square-bracketed parts.

Note that we do not allow this to recurse, i.e., if |[[X]]| substitutes into
text which itself contains a |[[...]]| notation, then we do not expand that
inner one. If we did, then the value of the bibliographic variable |[[Code]]|,
used by the HTML renderer, would cause a modest-sized explosion on some pages.

@<Make substitutions of square-bracketed variables in line@> =
	TEMPORARY_TEXT(rewritten);
	int slen, spos;
	while ((spos = Regexp::find_expansion(tl, '[', '[', ']', ']', &slen)) >= 0) {
		TEMPORARY_TEXT(varname);
		TEMPORARY_TEXT(substituted);
		TEMPORARY_TEXT(tail);
		Str::substr(rewritten, Str::start(tl), Str::at(tl, spos));
		Str::substr(varname, Str::at(tl, spos+2), Str::at(tl, spos+slen-2));
		Str::substr(tail, Str::at(tl, spos+slen), Str::end(tl));

		match_results mr = Regexp::create_mr();
		if (Bibliographic::data_exists(cls->for_web->md, varname)) {
			@<Substitute any bibliographic datum named@>;
		} else if (Regexp::match(&mr, varname, L"Navigation")) {
			@<Substitute Navigation@>;
		} else if (Regexp::match(&mr, varname, L"Breadcrumbs")) {
			@<Substitute Breadcrumbs@>;
		} else if (Str::eq_wide_string(varname, L"Plugins")) {
			@<Substitute Plugins@>;
		} else if (Regexp::match(&mr, varname, L"Complete (%c+)")) {
			text_stream *detail = mr.exp[0];
			@<Substitute a detail about the complete PDF@>;
		} else if (Regexp::match(&mr, varname, L"Module (%c+)")) {
			text_stream *detail = mr.exp[0];
			@<Substitute a Module@>;
		} else if (Regexp::match(&mr, varname, L"Chapter (%c+)")) {
			text_stream *detail = mr.exp[0];
			@<Substitute a Chapter@>;
		} else if (Regexp::match(&mr, varname, L"Section (%c+)")) {
			text_stream *detail = mr.exp[0];
			@<Substitute a Section@>;
		} else if (Regexp::match(&mr, varname, L"Docs")) {
			@<Substitute a Docs@>;
		} else if (Regexp::match(&mr, varname, L"Assets")) {
			@<Substitute an Assets@>;
		} else if (Regexp::match(&mr, varname, L"URL \"(%c+)\"")) {
			text_stream *link_text = mr.exp[0];
			@<Substitute a URL@>;
		} else if (Regexp::match(&mr, varname, L"Link \"(%c+)\"")) {
			text_stream *link_text = mr.exp[0];
			@<Substitute a Link@>;
		} else if (Regexp::match(&mr, varname, L"Menu \"(%c+)\"")) {
			text_stream *menu_name = mr.exp[0];
			@<Substitute a Menu@>;
		} else if (Regexp::match(&mr, varname, L"Item \"(%c+)\"")) {
			text_stream *item_name = mr.exp[0];
			text_stream *icon_text = NULL;
			@<Look for icon text@>;
			text_stream *link_text = item_name;
			@<Substitute a member Item@>;
		} else if (Regexp::match(&mr, varname, L"Item \"(%c+)\" -> (%c+)")) {
			text_stream *item_name = mr.exp[0];
			text_stream *link_text = mr.exp[1];
			text_stream *icon_text = NULL;
			@<Look for icon text@>;
			@<Substitute a general Item@>;
		} else {
			WRITE_TO(substituted, "%S", varname);
			if (Regexp::match(&mr, varname, L"%i+%c*"))
				PRINT("Warning: unable to resolve command '%S'\n", varname);
		}
		Regexp::dispose_of(&mr);
		Str::clear(tl);
		WRITE_TO(rewritten, "%S", substituted);
		WRITE_TO(tl, "%S", tail);
		DISCARD_TEXT(tail);
		DISCARD_TEXT(varname);
		DISCARD_TEXT(substituted);
	}
	WRITE_TO(rewritten, "%S", tl);
	Str::clear(tl); Str::copy(tl, rewritten);
	DISCARD_TEXT(rewritten);

@ This is why, for instance, |[[Author]]| is replaced by the author's name:

@<Substitute any bibliographic datum named@> =
	WRITE_TO(substituted, "%S", Bibliographic::get_datum(cls->for_web->md, varname));

@ |[[Navigation]]| substitutes to the content of the sidebar navigation file;
this will recursively call The Collater, in fact.

@<Substitute Navigation@> =
	if (cls->nav_file) {
		if (TextFiles::exists(cls->nav_file))
			Collater::collate(substituted, cls->for_web, cls->restrict_to_range,
				cls->nav_file, cls->nav_pattern, NULL, NULL, cls->wv, cls->into_file);
		else
			Errors::fatal_with_file("unable to find navigation file", cls->nav_file);
	} else {
		PRINT("Warning: no sidebar links will be generated, as -navigation is unset");
	}

@ A trail of breadcrumbs, used for overhead navigation in web pages.

@<Substitute Breadcrumbs@> =
	Colonies::drop_initial_breadcrumbs(substituted, cls->into_file,
		cls->crumbs);

@<Substitute Plugins@> =
	Assets::include_relevant_plugins(OUT, cls->nav_pattern, cls->for_web,
		cls->wv, cls->into_file);

@ We store little about the complete-web-in-one-file PDF:

@<Substitute a detail about the complete PDF@> =
	if (swarm_leader)
		if (Formats::substitute_post_processing_data(substituted,
			swarm_leader, detail, cls->nav_pattern) == FALSE)
			WRITE_TO(substituted, "%S for complete web", detail);

@ And here for Modules:

@<Substitute a Module@> =
	module *M = CONTENT_IN_ITEM(
		Collater::heading_topmost_on_stack(cls, MODULE_LEVEL), module);
	if (M == NULL)
		Errors::at_position("no module is currently selected",
			cls->errors_at, lpos);
	else @<Substitute a detail about the currently selected Module@>;

@<Substitute a detail about the currently selected Module@> =
	if (Str::eq_wide_string(detail, L"Title")) {
		text_stream *owner = Collater::module_owner(M, cls->for_web);
		if (Str::len(owner) > 0) WRITE_TO(substituted, "%S/", owner);
		WRITE_TO(substituted, "%S", M->module_name);
	} else if (Str::eq_wide_string(detail, L"Page")) {
		if (Colonies::find(M->module_name))
			Colonies::reference_URL(substituted, M->module_name, cls->into_file);
	} else if (Str::eq_wide_string(detail, L"Purpose")) {
		TEMPORARY_TEXT(url);
		WRITE_TO(url, "%p", M->module_location);
		Readme::write_var(substituted, url, I"Purpose");
		DISCARD_TEXT(url);		
	} else {
		WRITE_TO(substituted, "%S for %S", varname, M->module_name);
	}

@ And here for Chapters:

@<Substitute a Chapter@> =
	chapter *C = CONTENT_IN_ITEM(
		Collater::heading_topmost_on_stack(cls, CHAPTER_LEVEL), chapter);
	if (C == NULL)
		Errors::at_position("no chapter is currently selected",
			cls->errors_at, lpos);
	else @<Substitute a detail about the currently selected Chapter@>;

@<Substitute a detail about the currently selected Chapter@> =
	if (Str::eq_wide_string(detail, L"Title")) {
		Str::copy(substituted, C->md->ch_title);
	} else if (Str::eq_wide_string(detail, L"Code")) {
		Str::copy(substituted, C->md->ch_range);
	} else if (Str::eq_wide_string(detail, L"Purpose")) {
		Str::copy(substituted, C->md->rubric);
	} else if (Formats::substitute_post_processing_data(substituted,
		C->ch_weave, detail, cls->nav_pattern)) {
		;
	} else {
		WRITE_TO(substituted, "%S for %S", varname, C->md->ch_title);
	}

@ And this is a very similar construction for Sections.

@<Substitute a Section@> =
	section *S = CONTENT_IN_ITEM(
		Collater::heading_topmost_on_stack(cls, SECTION_LEVEL), section);
	if (S == NULL)
		Errors::at_position("no section is currently selected",
			cls->errors_at, lpos);
	else @<Substitute a detail about the currently selected Section@>;

@<Substitute a detail about the currently selected Section@> =
	if (Str::eq_wide_string(detail, L"Title")) {
		Str::copy(substituted, S->md->sect_title);
	} else if (Str::eq_wide_string(detail, L"Purpose")) {
		Str::copy(substituted, S->sect_purpose);
	} else if (Str::eq_wide_string(detail, L"Code")) {
		Str::copy(substituted, S->md->sect_range);
	} else if (Str::eq_wide_string(detail, L"Lines")) {
		WRITE_TO(substituted, "%d", S->sect_extent);
	} else if (Str::eq_wide_string(detail, L"Source")) {
		WRITE_TO(substituted, "%f", S->md->source_file_for_section);
	} else if (Str::eq_wide_string(detail, L"Page")) {
		Colonies::section_URL(substituted, S->md);
	} else if (Str::eq_wide_string(detail, L"Paragraphs")) {
		WRITE_TO(substituted, "%d", S->sect_paragraphs);
	} else if (Str::eq_wide_string(detail, L"Mean")) {
		int denom = S->sect_paragraphs;
		if (denom == 0) denom = 1;
		WRITE_TO(substituted, "%d", S->sect_extent/denom);
	} else if (Formats::substitute_post_processing_data(substituted,
		S->sect_weave, detail, cls->nav_pattern)) {
		;
	} else {
		WRITE_TO(substituted, "%S for %S", varname, S->md->sect_title);
	}

@ These commands are all used in constructing relative URLs, especially for
navigation purposes.

@<Substitute a Docs@> =
	Pathnames::relative_URL(substituted,
		Filenames::up(cls->into_file),
		Pathnames::from_text(Colonies::home()));

@<Substitute an Assets@> =
	pathname *P = Colonies::assets_path();
	if (P == NULL) P = Filenames::up(cls->into_file);
	Pathnames::relative_URL(substituted,
		Filenames::up(cls->into_file), P);

@<Substitute a URL@> =
	Pathnames::relative_URL(substituted,
		Filenames::up(cls->into_file),
		Pathnames::from_text(link_text));

@<Substitute a Link@> =
	WRITE_TO(substituted, "<a href=\"");
	Colonies::reference_URL(substituted, link_text, cls->into_file);
	WRITE_TO(substituted, "\">");

@<Substitute a Menu@> =
	if (cls->inside_navigation_submenu) WRITE_TO(substituted, "</ul>");
	WRITE_TO(substituted, "<h2>%S</h2><ul>", menu_name);
	cls->inside_navigation_submenu = TRUE;

@<Look for icon text@> =
	match_results mr = Regexp::create_mr();
	if (Regexp::match(&mr, item_name, L"<(%i+.%i+)> *(%c*)")) {
		icon_text = Str::duplicate(mr.exp[0]);
		item_name = Str::duplicate(mr.exp[1]);
	} else if (Regexp::match(&mr, item_name, L"(%c*?) *<(%i+.%i+)>")) {
		icon_text = Str::duplicate(mr.exp[1]);
		item_name = Str::duplicate(mr.exp[0]);
	}
	Regexp::dispose_of(&mr);

@<Substitute a member Item@> =
	TEMPORARY_TEXT(url);
	Colonies::reference_URL(url, link_text, cls->into_file);
	@<Substitute an item at this URL@>;
	DISCARD_TEXT(url);

@<Substitute a general Item@> =
	TEMPORARY_TEXT(url);
	Colonies::link_URL(url, link_text, cls->into_file);
	@<Substitute an item at this URL@>;
	DISCARD_TEXT(url);

@<Substitute an item at this URL@> =
	if (cls->inside_navigation_submenu == FALSE) WRITE_TO(substituted, "<ul>");
	cls->inside_navigation_submenu = TRUE;
	WRITE_TO(substituted, "<li>");
	if (Str::eq(url, Filenames::get_leafname(cls->into_file))) {
		WRITE_TO(substituted, "<span class=\"unlink\">");
		@<Substitute icon and name@>;
		WRITE_TO(substituted, "</span>");
	} else if (Str::eq(url, I"index.html")) {
		WRITE_TO(substituted, "<a href=\"%S\">", url);
		WRITE_TO(substituted, "<span class=\"selectedlink\">");
		@<Substitute icon and name@>;
		WRITE_TO(substituted, "</span>");
		WRITE_TO(substituted, "</a>");
	} else {
		WRITE_TO(substituted, "<a href=\"%S\">", url);
		@<Substitute icon and name@>;
		WRITE_TO(substituted, "</a>");
	}
	WRITE_TO(substituted, "</li>");

@<Substitute icon and name@> =
	if (Str::len(icon_text) > 0) {
		WRITE_TO(substituted, "<img src=\"");
		pathname *I = Colonies::assets_path();
		if (I == NULL) I = Pathnames::from_text(Colonies::home());
		Pathnames::relative_URL(substituted,
			Filenames::up(cls->into_file), I);
		WRITE_TO(substituted, "%S\" height=18> ", icon_text);
	}
	WRITE_TO(substituted, "%S", item_name);

@ This is a utility for finding the owner of a module, returning |NULL| (the
empty text) if it appears to belong to the current web |W|.

=
text_stream *Collater::module_owner(const module *M, web *W) {
	text_stream *owner =
		Pathnames::directory_name(Pathnames::up(M->module_location));
	text_stream *me = NULL;
	if ((W) && (W->md->path_to_web))
		me = Pathnames::directory_name(W->md->path_to_web);
	if (Str::ne_insensitive(me, owner)) return owner;
	return NULL;
}

@ This enables us to sort them. The empty owner (i.e., the current web) comes
top, then all other owners, in alphabetical order, and then last of all Inweb,
so that //foundation// will always be at the bottom.

=
web *sorting_web = NULL;
void Collater::sort_web(web *W) {
	sorting_web = W;
}
int Collater::sort_comparison(const void *ent1, const void *ent2) {
	const module *M1 = *((const module **) ent1);
	const module *M2 = *((const module **) ent2);
	text_stream *O1 = Collater::module_owner(M1, sorting_web);
	text_stream *O2 = Collater::module_owner(M2, sorting_web);
	int r = Collater::cmp_owners(O1, O2);
	if (r != 0) return r;
	return Str::cmp_insensitive(M1->module_name, M2->module_name);
}

int Collater::cmp_owners(text_stream *O1, text_stream *O2) {
	if (Str::len(O1) == 0) {
		if (Str::len(O2) > 0) return -1;
		return 0;
	}
	if (Str::len(O2) == 0) return 1;
	if (Str::eq_insensitive(O1, I"inweb")) {
		if (Str::eq_insensitive(O2, I"inweb") == FALSE) return 1;
		return 0;
	}
	if (Str::eq_insensitive(O2, I"inweb")) return -1;
	return Str::cmp_insensitive(O1, O2);
}
