// vim:syntax=lpc
#include <new_assert.h>

inherit PSYC.Handler.Base;

//! Client side (in respect to member<->channel) implementation of channel
//! communications.
//!
//! Handles the following Message Classes:
//! @ul
//! 	@item
//! 		_notice_context_enter_channel
//! 	@item
//! 		_notice_context_leave
//! @endul
//! Additionally filters out all messages from a group we are not in.
//!
//! Open-heartedly uses the "places" storage variable.
//!
//! Exports:
//! @ul
//! 	@item
//! 		@expr{enter()@}
//! 	@item
//! 		@expr{leave()@}
//! @endul

#define REQUESTED(x)	(x&1)
#define SUBSCRIBED(x)	(x&2)

/* How it works:
 *
 * request membership in a context
 * get a _notice_enter for the context and/or any of his channels
 *
 */

constant _ = ([
    "init" : ({ "places" }),
    "filter" : ([ 
	"" : ([ 
	    "wvars" : ({ "places" }),
	    "check" : "has_context",
	]),
    ]),
    "postfilter" : ([
	"_notice_context_enter_channel" : ([
	    "lock" : ({ "places" }),
	    "async" : 1,
	    "check" : "not_us",
       ]),
	"_notice_context_leave" : ([
	    "lock" : ({ "places" }),
	    "async" : 1,
	    "check" : "not_us",
	]),
    ]),
]);

constant export = ({
    "enter", "leave", "subscribe", "unsubscribe"
});

void init(mapping vars) {
    debug("init", 1, "Initing Handler.Subscribe of %O. vars: %O\n", parent, vars);
    
    if (!mappingp(vars["places"])) {
	void callback(int error, string key) {
	    if (error) {
		debug("init", "Absolutely fatal: initing handler did not work!!!\n");
	    } else {
		set_inited(1);
	    }
	};

	parent->storage->set("places", ([]), callback);
    } else {
	set_inited(1);
    }
}

int has_context(MMP.Packet p, mapping _m) {
    return has_index(p->vars, "_context");
}

int not_us(MMP.Packet p, mapping _m) {
    mapping vars = p->data->vars;

    if (has_index(p->vars, "_context")) {
	return 0;
    }

    if (p["_source_relay"] != uni) {
	// we did not leave!
	return 0;
    }

    if (has_index(vars, "_group")) {
	MMP.Uniform group = vars["_group"];
	if (group->channel ? group->super : group == uni) {
	    debug("packet_flow", 1, "not_us check is false for %O.\n", p);
	    return 0;
	}
    }
    
    return 1;
}

void postfilter_notice_context_leave(MMP.Packet p, mapping _v, mapping _m, function cb) {
    PSYC.Packet m = p->data;
    MMP.Uniform source = p->source();
    mixed sub = _v["places"];

    if (!mappingp(sub)) {
	parent->storage->unlock("places");
	enforcer(0, "places from storage not a mapping.\n");
    }

    void callback(int error) {
	if (error) {
	    debug("storage", 0, "set_unlock failed for places. retry... \n.");

	    // in most cases this will be a loop.. most certainly.
	    //  we should do something else here..
	    return;
	}

	call_out(cb, 0, PSYC.Handler.DISPLAY);
    };
    
    if (has_index(sub, source)) {
	m_delete(sub, source);

	parent->storage->set_unlock("places", sub, callback);
    } else {
	parent->storage->unlock("places");
	call_out(cb, 0, PSYC.Handler.DISPLAY);
    }
}

int filter(MMP.Packet p, mapping _v, mapping _m) {
    MMP.Uniform channel = p["_context"];

    // we have a check for that, messages without context never get here
    // if (!channel) return PSYC.Handler.GOON;

    mixed sub = _v["places"];
    if (!mappingp(sub)) {
	enforcer(0, "places from storage not a mapping.\n");
    }
    // we could aswell save the object of that channel into the uniform.. 
    // they are some somewhat related (instead of cutting the string everytime)
    if (channel->channel) {
	MMP.Uniform context = channel->super;

	if (!has_index(sub, channel)) {
	    if (has_index(sub, context)) {
		debug("multicast_routing", 0, "%O: %O forgot to join us into %O.\n", parent, context, channel);
	    } else {
		debug("multicast_routing", 0, "%O: we never joined %O but are getting messages from %O.\n", parent, context, channel);
	    }

	    // TODO: dont use leave() since we dont need to remove channel from
	    // places mapping
	    sendmsg(channel, PSYC.Packet("_request_context_leave_channel", ([ "_supplicant" : uni, "_group" : channel ])));

	    return PSYC.Handler.STOP;
	}
    } else if (!has_index(sub, channel)) {
	debug("multicast_routing", 0, "%O: we never joined %O but are getting messages.\n", parent, channel);
	//sendmsg(channel, PSYC.Packet("_notice_context_leave"));
	leave(channel);

	return PSYC.Handler.STOP;
    }

    return PSYC.Handler.GOON;
}

void postfilter_notice_context_enter_channel(MMP.Packet p, mapping _v, mapping _m, function cb) {
    PSYC.Packet m = p->data;
    MMP.Uniform member = m["_supplicant"];
    MMP.Uniform channel = m["_group"];

    mixed sub = _v["places"];
    if (!mappingp(sub)) {
	parent->storage->unlock("places");
	enforcer(0, "places from storage not a mapping.\n");
    }

    if (!channel->super) {
	// dum dump
	debug("protocol_error", 1, "%O: got channel join without channel from dump dump %O.\n", uni, p->source());
	parent->storage->unlock("places");
	call_out(cb, 0, PSYC.Handler.STOP);
	return;
    }

    if (!has_index(sub, channel->super)) {
	debug("protocol_error", 1, "%O: illegal channel join to %O from %O.\n", uni, channel, p->source());
	parent->storage->unlock("places");
	call_out(cb, 0, PSYC.Handler.STOP);
	return;
    }

    if (has_index(sub, channel)) {
	parent->storage->unlock("places");
    } else {
	sub[channel] = 1;
	parent->storage->set_unlock("places", sub);
    }

    call_out(cb, 0, PSYC.Handler.DISPLAY);
    return;
}

// ==================================

//! Unsubscribe from a channel.
//! @param channel
//! 	Channel to cancel subscription of.
void unsubscribe(MMP.Uniform channel) {
    if (!channel->channel) {
	parent->unfriend_symmetric(channel);
    } else {
	parent->leave(channel);
    }
}

//! Subscribe to a channel. This is a special term used for the request for 
//! membership in a place. Use this if you want a person to subscribe to a
//! chatroom (place). Friendship is offered to the place at the same time 
//! to allow the place to react on status changes (e.g. remove someone from
//! the talking channel in case he/she goes offline).
//! @param channel
//! 	Channel to subscribe. 	
//! @note
//! 	This subscription is permanent. It will last until it is canceled using
//! 	@[unsubscribe()].
void subscribe(MMP.Uniform channel) {
    MMP.Uniform place;
    enforcer(MMP.is_place(channel), "Subscription is made for places.\n");

    place = (channel->channel) ? channel->super : channel;
    
    void callback(int error) {
	if (error) {
	    debug("friendship", 0, "offer_quiet() in subscribe() failed.\n");
	} else {
	    enter(channel);
	}
    };

    parent->offer_quiet(place, callback);
}

//! Enters a channel.
//! @param channel
//! 	The channel to enter.
//! @param error_cb
//! 	Callback to be called on success or failure. Signature:
//! 	@expr{void error_cb(int error, mixed ... args);@}.
//! 	Retring may work here.
//! @param args
//! 	Arguments to be passed on to the @expr{error_cb@}.
//! @note 
//! 	This is a low-level method. Use @[subscribe()] to let a person
//! 	join a place.	
void enter(MMP.Uniform channel, function|void error_cb, mixed ... args) {

    void callback(MMP.Packet p, mapping _v, function cb) {
	PSYC.Packet m = p->data;
	MMP.Uniform source = p->source();

	MMP.Uniform group;
	if (!has_index(m->vars, "_group") || !objectp(group = m["_group"])) {
	    group = channel; 
	}

	void _error_cb(int error, string key, function error_cb, array(mixed) args) {
	    if (error) {
		debug("storage", 0, "unlocking in %O failed. thats fatal!!!\n", key);
	    } else if (error_cb) {
		error_cb(0, @args);	
	    } else {
		debug("channel_membership", 3, "enter() was successfull. but noone realized.\n");
	    }
	};

	mapping sub = _v["places"];

	if (PSYC.abbrev(m->mc, "_notice_context_enter")) {
	    if (has_index(sub, group)) {
		debug("channel_membership", 1, "%O: Double joined %O.\n", parent, group);
		parent->storage->unlock("places", _error_cb, error_cb, args);
	    } else {
		sub[group] = 1;
		parent->storage->set_unlock("places", sub, _error_cb, error_cb, args);
	    }
	} else if (PSYC.abbrev(m->mc, "_notice_context_discord")) {
	    parent->storage->unlock("places", _error_cb, error_cb, args);
	} else {
	    parent->storage->unlock("places", _error_cb, error_cb, args);
	}

	call_out(cb, 0, PSYC.Handler.DISPLAY);
    };

    send_tagged_v(uni->root, PSYC.Packet("_request_context_enter", ([ "_group" : channel, "_supplicant" : uni ])), 
		  ([ "lock" : (< "places" >), "async" : 1 ]), callback);
}

//! Leaves a channel.
//! @param channel
//! 	The channel to leave.
void leave(MMP.Uniform ... channels) {

    void callback(int error, string key, mapping sub) {
	if (error != PSYC.Storage.OK) {
	    debug("storage", 0, "leave(%O) failed because of storage.\n");
	    return;
	}

	void cb(int error, string key) {
	    if (error != PSYC.Storage.OK) {
		debug("storage", 0, "leave(%O) failed because of storage.\n");
	    }
	};

	int changed = 0;
	foreach (channels;;MMP.Uniform channel) {
	    if (has_index(sub, channel)) {
		m_delete(sub, channel);
		changed = 1;
	    }

	    PSYC.Packet request = PSYC.Packet("_request_context_leave", ([ "_group" : channel, "_supplicant" : uni ]));
	    sendmsg(uni->root, request);
	}

	if (changed) {
	    parent->storage->set_unlock("places", sub);
	} else {
	    parent->storage->unlock("places");
	    // could warn about desync here.. but it should be selfhealing anyways
	}
    };

    parent->storage->get_lock("places", callback);
}

