
object generate_default_type(array|string type, void|mapping overwrites) {
    // mapping(int:string|int)|array(mapping|
    array a = stringp(type) ? Parser.Pike.group(Parser.Pike.split(type)) : type;
    array b = ({});

OUTER: for (int i = 0; i < sizeof(a); i++) {
	string|array type = a[i];
	object sig;
	if (stringp(type)) {
	    type = String.trim_all_whites(type);
	}
	if (overwrites && overwrites[type]) {
	    sig = overwrites[type];
	} else switch (type) {
	case "\n":
	case "":
	case "|": continue OUTER;
	case "array":
	    if (!arrayp(a[i+1])) break;
	    sig = .Types.OneTypedList(generate_default_type(a[i+1][1..<1], overwrites));
	    i++;
	    break;
	case "mapping":
	    if (!arrayp(a[i+1])) break;
	    int pos = search(a[i+1], ":");
	    if (pos != -1) {
		sig = .Types.OneTypedMapping(generate_default_type(a[i+1][1..pos-1], overwrites),
					     generate_default_type(a[i+1][pos+1..<1], overwrites));
		i++;
	     }
	    break;
	case "string":
	    sig = .Types.String();
	    break;
	case "int":
	    sig = .Types.Int();
	    break;
	}
	if (sig) b += ({ sig });
	else error("Cannot generate parser for %O\n", type);
    }

    if (sizeof(b) > 1) {
	return .Types.Or(@b);
    } else if (sizeof(b)) {
	return b[0];
    } 
    error("Could not generate parser for %O\n", type);
}

class Resolver(mapping symbols) {
    mixed resolv(string idx) {
	return has_index(symbols, idx) ? symbols[idx] : master()->resolv(idx);
    }
}

string get_type(object o, string fname) {
    array tree = Program.inherit_tree(object_program(o));

    string low_get_type(program prog) {
	program p = compile_string(sprintf("string get_type(___prog o) { return sprintf(\"%%O\", typeof(o->%s)); }", fname), "-",
			       Resolver(([ "___prog" : prog, "`->" : (has_index(o, "`->") ? `[] : `->) ])));
	return p()->get_type(o);
    };

    string rec_get_type(program|array prog) {
	string t;

	if (arrayp(prog)) {
	    foreach (prog;; program|array p) {
		t = rec_get_type(p);
		if (t != "mixed") return t;
	    }
	} else {
	    t = low_get_type(prog);
	}
	if (t != "mixed") return t;
	return 0;
    };

    return rec_get_type(tree) || "mixed";
}

object generate_struct(object o, string type, void|function helper, void|mapping overwrites) {
    array(string) a = indices(o) - indices(object_program(o));
    mapping m = ([]);

    function lookup = has_value(a, "`->") ? `[] : `->;

    foreach (a;; string symbol) {
	if (functionp(lookup(o, symbol))) {
	    continue;
	}

	if (helper) {
	    mixed v =  helper(o, symbol);
	    if (v == -1) {
		continue;
	    } else if (v) {
		m[symbol] = v;
		continue;
	    }
	}

	//werror("%O\n", o->_types);

	//werror("symbol(%O): %s %s\n", object_program(o), get_type(o, symbol), symbol);
	mixed err = catch { 
	    if (mappingp(o->_types) && o->_types[symbol]) {
		int|string|object t = o->_types[symbol];
		if (t == -1) continue;
		if (stringp(t))
		    t = generate_default_type(t, overwrites);
		m[symbol] = t;
	    } else 
		m[symbol] = generate_default_type(get_type(o, symbol), overwrites);
	};
	if (err) {
	    werror("Failed to generate type for %s in %O\n", symbol, o);
	    throw(err);
	}
    }

    return .Types.Struct(type, m, object_program(o));
}

object generate_structs(mapping m, void|function helper, void|mapping overwrites) {
    object p = Serialization.Types.Polymorphic();
    foreach (m; string type; object o) {
	mixed err = catch {
	    p->register_type(object_program(o), type, generate_struct(o, type, helper, overwrites));
	};
	if (err) {
	    werror("Failed to compile property in object %O (atom type: %s).\n", o, type);
	    throw(err);
	}
    }
    return p;
}