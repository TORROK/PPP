// vim:syntax=lpc
//
#include <debug.h>
#define THROW(s)        throw(({ (s), backtrace() }))
#if DEBUG
void debug(string cl, string format, mixed ... args) {
    // erstmal nix weiter
    predef::werror("(%s)\t"+format, cl, @args);
}
#endif

string|String.Buffer render_vars(mapping(string:mixed) vars, 
				 void|String.Buffer to) {
    String.Buffer p;
    // i do not remember what i needed the p for.. we could use to instead.
    if (to)
	p = to;	
    else 
	p = String.Buffer();

    function add = p->add;
    function putchar = p->putchar;

    if (mappingp(vars)) foreach (vars; string key; mixed val) {
	string mod;
	if (key[0] == '_') mod = ":";
	else mod = key[0..0];
	

	// we have to decide between deletions.. and "".. or 0.. or it
	// a int zero not allowed?
	if (val) {
	    if (key[0] == '_') putchar(':');
	    add(key);
	    putchar('\t');
	    
	    if (stringp(val))
		add(replace(val, "\n", "\n\t")); 
	    else if (arrayp(val))
		add(map(val, replace, "\n", "\n\t") * ("\n"+mod+"\t"));
	    else if (mappingp(val))
		add("dummy");
	    else if (intp(val))
		add((string)val);
	    
	    putchar('\n');
	
	} else {
	    if (key[0] == '_') putchar(':');
	    add(key);
	    putchar('\n');
	}
    }
}

string|String.Buffer render(mmp_p packet, void|String.Buffer to) {
    String.Buffer p;

    if (to)
	p = to;	
    else 
	p = String.Buffer();

    function add = p->add;
    function putchar = p->putchar;

    if (sizeof(packet->vars))
	MMP.render_vars(packet->vars, p);

    if (packet->data) { 
	putchar('\n');
    
	if (stringp(packet->data)) {
	    add(packet->data);
	} else {
	    // TODO: every object contained in data needs a 
	    // render(void|String.Buffer) method.
	    add((string)packet->data);
	}
	add("\n.\n");
    } else {
	add(".\n");
    }

    if (to)
	return p;
    return p->get();
}

class mmp_p {
    mapping(string:mixed) vars;
    string|object data;

    // experimental variable family inheritance...
    // this actually does not exactly what we want.. 
    // because asking for a _source should return even _source_relay 
    // or _source_technical if present...
    void create(void|string|object d, void|mapping(string:mixed) v) {
	vars = v||([]);
	data = d||0; 
    }

    mixed cast(string type) {
	if (type == "string") {
	    return MMP.render(this);
	}
    }

    string next() {
	return (string)this;
    }

    int has_next() { 
	return 0;
    }

    string _sprintf(int type) {
	if (type == 'O') {
	    if (data == 0) {
		return "MMP.mmp_p(Empty)\n";
	    }

	    return sprintf("MMP.mmp_p(%O, '%.15s..' )\n", vars, (string)data);
	}

	return UNDEFINED;
    }
    
    mixed `[](string id) {
	if (has_index(vars, id)) {
	    return vars[id];
	}

	if (!is_mmpvar(id) && objectp(data)) {
	    return data[id];
	}

	return UNDEFINED;
    }

    mixed `[]=(string id, mixed val) {

	if (is_mmpvar(id)) {
	    return vars[id] = val;
	}
	
	if (objectp(data)) {
	    return data[id] = val;
	}

	throw(({ sprintf("cannot assign values to data, and %O is not am mmp "
			 "variable.", id), backtrace() }));
    }
}

// 0
// 1 means yes and merge it into psyc
// 2 means yes but do not merge

int(0..2) is_mmpvar(string var) {
    switch (var) {
    case "_target":
    case "_source":
    case "_source_relay":
    case "_source_location":
    case "_source_identification":
    case "_context":
    case "_length":
    case "_counter":
    case "_reply":
    case "_trace":
	return 1;
    case "_amount_fragments":
    case "_fragment":
    case "_encoding":
    case "_list_require_modules":
    case "_list_require_encoding":
    case "_list_require_protocols":
    case "_list_using_protocols":
    case "_list_using_modules":
    case "_list_understand_protocols":
    case "_list_understand_modules":
    case "_list_understand_encoding":
	return 2;
    }
    return 0;
}

class Circuit {
    inherit MMP.Utils.Queue;

    Stdio.File|Stdio.FILE socket;
    string|String.Buffer inbuf;
#ifdef LOVE_TELNET
    string dl;
#endif
    MMP.Utils.Queue q_neg = MMP.Utils.Queue();
    mmp_p inpacket;
    string|array(string) lastval; // mappings are not supported in psyc right
				  // now anyway..
    int lastmod, write_ready, write_okay; // sending may be forbidden during
					  // certain parts of neg
    string lastkey, peerhost;
    function msg_cb, close_cb;

    // bytes missing in buf to complete the packet inpacket. (means: inpacket 
    // has _length )
    // start parsing at byte start_parse. start_parse == 0 means create a new
    // packet.
    int m_bytes, start_parse;

    // cb(received & parsed mmp_message);
    //
    // on close/error:
    // closecb(0); if connections gets closed,
    // 	 --> DISCUSS: closecb(string logmessage); on error? <--
    // 	 maybe: closecb(object dings, void|string error)
    void create(Stdio.File|Stdio.FILE so, function cb, function closecb
		) {
	P2(("MMP.Circuit", "create(%O, %O, %O)\n", so, cb, closecb))
	socket = so;
	socket->set_nonblocking(start_read, write, close);
	peerhost = so->query_address();
	msg_cb = cb;
	close_cb = closecb;

	reset();
	//::create();
    }

    void reset() {
	lastval = lastkey = lastmod = 0;
	inpacket = mmp_p();
    }	

    void activate() {
	write_okay = 1;
	if (write_ready)
	    write();
    }

    void send_neg(mmp_p mmp) {
P0(("MMP.Circuit", "%O->send_neg(%O)\n", this, mmp))
	q_neg->push(mmp);

	if (write_ready) {
	    write();
	}
    }

    void send(mmp_p mmp) {
P0(("MMP.Circuit", "%O->send(%O)\n", this, mmp))
	push(mmp);

	if (write_ready) {
	    write();
	}
    }

    int write(void|mixed id) {
	MMP.Utils.Queue currentQ;
	// we could go for speed with
	// function currentshift, currentunshift;
	// as we'd only have to do the -> lookup for q_neg packages then ,)
	
	if (!write_okay) return (write_ready = 1, 0);

	if (!q_neg->isEmpty()) {
	    currentQ = q_neg;
	    P2(("MMP.Circuit", "Negotiation stuff..\n"))
	} else if (!isEmpty()) {
	    currentQ = this;
	    P2(("MMP.Circuit", "Normal queue...\n"))
	} 
#if DEBUG
	else {
	    P2(("MMP.Circuit", "No packets in queue.\n"))
	}
#endif

	if (!currentQ) {
	    write_ready = 1;
	} else {
	    int written;
	    mixed tmp;
	    string s;

	    write_ready = 0;

	    tmp = currentQ->shift();

	    if (arrayp(tmp)) {
		[s, tmp] = tmp;
		// it seems more logical to me, to put all this logic into
		// close.
		if (tmp) shift();
	    } else /* if (objectp(tmp)) */ {
		s = tmp->next();
		if (tmp->has_next()) {
		    currentQ->enqueue(tmp);
		    currentQ = 0;
		}
		// TODO: HOOK
	    }

	    // TODO: encode
	    //s = trigger("encode", s);
	    written = socket->write(s);

	    P2(("MMP.Circuit", "%O wrote %d (of %d) bytes.\n", this, written, 
		sizeof(s)))

	    if (written != sizeof(s)) {
		if (currentQ == this) {
		    q_neg->unshift(({ s[written..], tmp }));
		    unshift(tmp);	
		} else {
		    q_neg->unshift(({ s[written..], 0 }));
		}
	    }
	}

	return 1;
    }

    int start_read(mixed id, string data) {

	// is there anyone who would send \n\r ???
#ifdef LOVE_TELNET
	if (data[0 .. 2] == ".\n\r") {
	    dl = "\n\r";
	} else if (data[0 .. 2] == ".\r\n") {
	    dl = "\r\n";
	} else 
#endif
	if (data[0 .. 1] != ".\n") {
	    // TODO: error message
	    socket->close();
	    close_cb(this);
	    return 1;
	}
P2(("MMP.Circuit", "%s sent a proper initialisation packet.\n", peerhost))
#ifdef LOVE_TELNET
	if (sizeof(data) > ((dl) ? 3 : 2)) {
	    read(0, data[((dl) ? 3 : 2) ..]);
	}
#else 
	if (sizeof(data) > 2) {
	    read(0, data[2 ..]);
	}

#endif
	socket->set_read_callback(read);
    }

    int read(mixed id, string data) {
	int ret = 0;
	// TODO: decode

	P2(("MMP.Circuit", "read %d bytes.\n", sizeof(data)))

	if (!inbuf)
	    inbuf = data;
	else if (stringp(inbuf)) {
	    if (m_bytes && 0 < (m_bytes -= sizeof(data))) {
		// create a String.Buffer
		String.Buffer t = String.Buffer(sizeof(inbuf)+m_bytes);
		t += inbuf;
		t += data;
		inbuf = t;
		// dont try to parse again
		return 1;
	    }
	    inbuf += data;
	} else {
	    m_bytes -= sizeof(data);
	    inbuf += data;
	    if (0 < m_bytes) return 1;

	    // create a string since we will try to parse..
	    inbuf = inbuf->get();
	}

	array(mixed) exeption;
	if (exeption = catch {
	    while (inbuf && !(ret = 
#ifdef LOVE_TELNET
	(dl) ? parse(dl) :
#endif
		     parse()
		     )) {
		P2(("MMP.Circuit", "parsed %O.\n", inpacket))
		if (inpacket->data) {
		    // TODO: HOOK
		    msg_cb(inpacket, this);
		    reset(); // watch out. this may produce strange bugs...
		} else {
		    P2(("MMP.Circuit", "Got a ping.\n"))
		}
	    }
	    if (ret > 0) m_bytes = ret;
	}) {
	    P0(("MMP.Circuit", "Catched an error: '%s' backtrace: %O\n", @exeption))
	    // TODO: error message
	    close_cb(this);
	    socket->close();
	}


	return 1;	
    }

    int close(mixed id) {
	// TODO: error message
	close_cb(this);
    }

    // works quite similar to the psyc-parser. we may think about sharing some
    // source-code. 
#ifdef LOVE_TELNET
# define LL	sizeof(linebreak)
# define LD	linebreak
    int parse(void|string linebreak) {
	if (!linebreak) linebreak = "\n";
#else
    int parse() {
# define LL	1
# define LD	"\n"
#endif

#define RETURN(x)	ret = (x); stop = -1
#define INBUF	((string)inbuf)
	string key, val;
	int mod, start, stop, num, ret;

	ret = -1;

	// expects to be called only if inbuf is nonempty
	
	P2(("MMP.Parse", "parsing: %d from position %d\n", sizeof(inbuf), 
		      start_parse))
LINE:	while(-1 < stop && 
	      -1 < (stop = (start = (mod) ? stop+LL : start_parse, 
			    search(inbuf, LD, start)))) {
	    // TODO: we could do start_parse = stop+LL here since
	    // 	     all failures throw anyway..

	    // check for an empty line.. start == stop
	    mod = INBUF[start];
	    P2(("MMP.Parse", "start: %d, stop: %d. mod: %c\n", start, stop, mod))
	    P2(("MMP.Parse", "parsing line: '%s'\n", INBUF[start .. stop-1]))
	    if (stop > start) switch(mod) {
	    case '.':
		// empty packet. should be accepted in any case.. 
		// this may become a PING-PONG strategy
		//
		// it may be wrong to make a difference between packets without
		// newline as delimiter.. and those with and without data..
		inpacket->data = 0;
		inbuf = INBUF[stop+LL .. ];
		RETURN(0);
		break;
	    case '=':
	    case '+':
	    case '-':
	    case '?':
	    case ':':
#ifdef LOVE_TELNET
		num = sscanf(INBUF[start+1 .. stop-1], "%[A-Za-z_]%*[\t ]%s",
#else
		num = sscanf(INBUF[start+1 .. stop-1], "%[A-Za-z_]\t%s",
#endif
			     key, val);
		if (num == 0) THROW("parsing error");
		// this is either an empty string or a delete. we have to decide
		// on that.
		start_parse = stop+LL;
		P2(("MMP.Parse", "%s => %O \n", key, val))
		if (num == 1) val = 0;
		else if (key == "") {
		   if (mod != lastmod) THROW("improper list continuation");
		   if (mod == '-') THROW( "diminishing lists is not supported");
		   if (!arrayp(lastval)) 
			lastval = ({ lastval, val });
		   else lastval += ({ val });
		   continue LINE;
		}
		break;
	    case '\t':
		if (!lastmod) THROW( "invalid variable continuation");
P2(("MMP.Parse", "mmp-parse: + %s\n", INBUF[start+1 .. stop-1]))
		if (arrayp(lastval))
		    lastval[-1] += "\n" +INBUF[start+1 .. stop-1];
		else
		    lastval += "\n" +INBUF[start+1 .. stop-1];
		continue LINE;
	    default:
		THROW("unknown modifier "+String.int2char(mod));

	    } else {
		// this else is an empty line.. 
		// allow for different line-delimiters
		int length = inpacket["_length"];

		if (length) {
		    if (stop+LL + length > sizeof(inbuf)) {
			start_parse = start;
P2(("MMP.Parse", 
    "reached the data-part. %d bytes missing (_length specified)\n", 
    stop+LL+length-sizeof(inbuf)))
			RETURN(stop+LL+length-sizeof(inbuf));
		    } else {
			// TODO: we have to check if the packet-delimiter
			// is _really_ there. and throw otherwise
			inpacket->data = INBUF[stop+LL .. stop+LL+length];
			if (sizeof(inbuf) == stop+3*LL+length+1)
			    inbuf = 0;
			else
			    inbuf = INBUF[stop+length+3*LL+1 .. ];
			start_parse = 0;
P2(("MMP.Parse", "reached the data-part. finished. (_length specified)\n", ))
			RETURN(0);
		    }
		    // TODO: we could cache the last sizeof(inbuf) for failed
		    // searches.. 
		} else if (-1 == (length = search(inbuf, LD+"."+LD, stop+LL))) {
		    start_parse = start;
P2(("MMP.Parse", "reached the data-part. i dont know how much is missing.\n", ))
		    RETURN(-1);
		} else {
		    inpacket->data = INBUF[stop+LL .. length];	
		    if (sizeof(inbuf) == length+2*LL+1)
			inbuf = 0;
		    else
			inbuf = INBUF[length+2*LL+1 .. ];
		    start_parse = 0;
P2(("MMP.Parse", "reached the data-part. finished.\n", ))
		    RETURN(0);
		}
	    }

	    if (lastkey) {
		inpacket[lastkey] = lastval;
	    }

	    lastmod = mod;
	    lastkey = key;
	    lastval = val;

	}

	return ret;
    }
#undef INBUF
#undef RETURN(x)
#undef LL
#undef LD
}

class Active {
    inherit Circuit;

    void start_read(mixed id, string data) {
	::start_read(id, data);

	send_neg(mmp_p());
    }
}

class Server {
    inherit Circuit;

    void create(Stdio.File|Stdio.FILE so, function cb, function closecb) {
	::create(so, cb, closecb);

	q_neg->unshift(mmp_p());
	activate();
    }

#ifdef LOVE_TELNET
    int parse(void|string ld) {
	int ret = ::parse(ld);
#else
    int parse() {
	int ret = ::parse();
#endif

	if (ret == 0) {
	    if (inpacket->data == 0 && !sizeof(inpacket->vars)) {
		send_neg(mmp_p());
	    }
	}

	return ret;
    }
}