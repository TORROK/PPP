// vim:syntax=ragel
#include <stdio.h>
#include "global.h"
#include "interpret.h"
#include "stralloc.h"
#include "mapping.h"
#include "svalue.h"
#include "array.h"
#include "builtin_functions.h"
#include "module.h"

char *_parse_JSON(char* p, char* pe, 
#ifndef USE_PIKE_STACK
		  struct svalue *var, 
#endif
		  struct string_builder *s); 
char *_parse_JSON_mapping(char* p, char* pe, 
#ifndef USE_PIKE_STACK
			  struct svalue *var, 
#endif
			  struct string_builder *s); 
char *_parse_JSON_array(char* p, char* pe, 
#ifndef USE_PIKE_STACK
			struct svalue *var, 
#endif
			struct string_builder *s); 
char *_parse_JSON_number(char* p, char* pe, 
#ifndef USE_PIKE_STACK
			 struct svalue *var, 
#endif
			 struct string_builder *s); 
char *_parse_JSON_string(char* p, char* pe, 
#ifndef USE_PIKE_STACK
			 struct svalue *var, 
#endif
			 struct string_builder *s); 

#include "json_string.c"
#include "json_number.c"
#include "json_array.c"
#include "json_mapping.c"

%%{
    machine JSON;
    write data;

    action parse_string {
	i = _parse_JSON_string(fpc, pe, 
#ifndef USE_PIKE_STACK
			       var, 
#endif
			       s);
#ifndef USE_PIKE_STACK
	if (i == NULL) fbreak;
#endif
	fexec i;
    }

    action parse_mapping {
	i = _parse_JSON_mapping(fpc, pe, 
#ifndef USE_PIKE_STACK
				var, 
#endif
				s);
#ifndef USE_PIKE_STACK
	if (i == NULL) fbreak;
#endif
	fexec i;
    }

    action parse_array {
	i = _parse_JSON_array(fpc, pe, 
#ifndef USE_PIKE_STACK
			      var, 
#endif
			      s);
#ifndef USE_PIKE_STACK
	if (i == NULL) fbreak;
#endif
	fexec i;
    }

    action parse_number {
	i = _parse_JSON_number(fpc, pe, 
#ifndef USE_PIKE_STACK
			       var, 
#endif
			       s);
#ifndef USE_PIKE_STACK
	if (i == NULL) fbreak;
#endif
	fexec i;
    }

    number_start = [\-+.] | digit;
    array_start = '[';
    mapping_start = '{';
    string_start = '"';
    value_start = number_start | array_start | mapping_start | string_start;
    myspace = ' ';

    main := myspace* . (number_start >parse_number |
			string_start >parse_string |
			mapping_start >parse_mapping |
			array_start >parse_array |
			'true' @{ push_int(1); } |
			'false' @{ push_undefined(); } |
			'null' @{ push_int(0); } ) . myspace* %*{ fbreak; };
}%%

char *_parse_JSON(char *p, char *pe, 
#ifndef USE_PIKE_STACK
		  struct svalue *var, 
#endif
		  struct string_builder *s) {
    char *i = p;
    int cs;

    %% write init;
    %% write exec;

    if (
#ifndef USE_PIKE_STACK
	i != NULL && 
#endif
	cs >= JSON_first_final) {
	return p;
    }
#ifndef USE_PIKE_STACK
    Pike_error("Error parsing JSON at '%.*s'\n", MINIMUM((int)(pe - p), 10), p);
#endif
    return NULL;
}

/*! @module Public
 */

/*! @module Parser
 */

/*! @module PSYC
 */

/*! @decl array|mapping|string|float|int parse_JSON(string s)
 *!
 *! Parses a JSON-formatted string and returns the corresponding pike data type.
 */
PIKEFUN mixed parse(string data) {
    struct string_builder s;
    init_string_builder(&s, 1);
#ifndef USE_PIKE_STACK
    struct svalue *var;
#endif
    char *ret;
    // we wont be building more than one string at once.

#ifndef USE_PIKE_STACK
    var = (struct svalue *)malloc(sizeof(struct svalue));

    if (var == NULL) {
	Pike_error("malloc failed during JSON parse.\n");
    }

    memset(var, 0, sizeof(struct svalue));
#endif

    if (data->size_shift != 0) {
	Pike_error("Size shift != 0.");
	// no need to return. does a longjmp
    }

    pop_stack();
    ret = (char*)STR0(data);
    ret = _parse_JSON(ret, ret + data->len, 
#ifndef USE_PIKE_STACK
		      var, 
#endif
		      &s);

#ifndef USE_PIKE_STACK
    if (ret == NULL) {
	free(var);
	Pike_error("Error while parsing JSON!\n");
    }
#endif

#ifndef USE_PIKE_STACK
    push_svalue(var);
#endif
    return;
}
