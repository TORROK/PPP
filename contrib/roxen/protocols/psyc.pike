// This is a roxen protokol module. 
// (c) 2007 Arne Goedeke, Martin Bähr, Tobias S. Josefowitz, Webhaven
//
// psyc.pike
// Roxen PSYC Protocol
// glue for the PSYC protocol.

constant cvs_version="$Id: psyc.pike,v 0.1 mbaehr Exp $";

#define DEBUG 0

constant version = "1.0";

object my_fd; // The file descriptor
object port_obj; // The port object
object conf;  // The current configuration

mapping (string:mixed)  misc = ([ ]);
string localhost; // Name of the psyc server.
string localaddr; // IP address
int localport;

object pipe; // The pipe...
object r_lock;

string remoteaddr; // Remote IP address.
string remotehost; // Remote host name.
string ident;

void disconnect() {
  my_fd = 0;
  destruct();
}

void send(string what, array(int)|int|void code, int|void host);

void end(string|void s, array(int)|int|void code) {
  if(objectp(my_fd)) {
    catch {
      my_fd->set_close_callback(0);
      my_fd->set_read_callback(0);
      my_fd->set_blocking();
      send(s, code);
      my_fd->close();
      destruct(my_fd);
    };
    my_fd = 0;
  }
  disconnect();  
}


mixed handle_psyc(mixed cmd, mixed args) 
{
  mixed out;
  out = this_object()->conf->call_provider("psyc","handle_psyc",this_object(),cmd,args);
  //werror("PSYC: %O, %O, %O, %O\n", cmd, args, out, this_object()->conf->get_providers("psyc"));
  return out;
}

mixed log_psyc(mixed cmd, mixed args, mixed out, array(int)|int|void error, int|void size) 
{
  //werror("PSYC: %O, %O, %O, %O, %O, %O\n", cmd, args, out, error, size, this_object()->conf->get_providers("psyc_logger"));
  return this_object()->conf->call_provider("psyc_logger","log_psyc",this_object(),cmd, args, out, error, size||0);
}


// Some data arrived on the socket...
void got_data(mixed _id, string data);

void create(object f, object c, object cc) {

  if(f) {
    my_fd=f;
    if( c ) port_obj = c;
    if( cc ) conf = cc;
    //dns=Protocols.DNS.client();
    array tmp;

    catch(remoteaddr=((my_fd->query_address()||"")/" ")[0]);
    localhost = gethostname();
    localaddr = gethostbyname(localhost)[1][0];
    remotehost = roxen->blocking_ip_to_host(remoteaddr);
    create_server();
    werror("Psychaven %s:%O\n", localhost, port_obj->servers);

    array connectedaddr; 
    int connectedport;
    object flashfile;
    [connectedaddr, connectedport] = array_sscanf(f->query_address(1), "%{%d.%d.%d.%d%} %d");
    if ( connectedport < 1024 )
    {
      flashfile = MMP.Utils.FlashFile(MMP.Utils.CrossDomainPolicy(localhost, connectedport));
      flashfile->assign(f);
      f = flashfile;
    }
      
    port_obj->servers[conf]->add_socket(f);
  }
}


string text_db_path = "../psyced/world/default/";
// string text_db_path = "../default/";
string data_path = "/usr/local/roxen/local/psyc_data/";
string hostname;
string bind;


void create_server()
{
  werror("Psychaven create_server() %s:%O\n", localhost, port_obj->servers);
  if (!port_obj->servers[conf])
  {
    
    if (!hostname)
      hostname = gethostname()||localhost||"localhost";
    if (!localhost)
      localhost = gethostbyname(hostname)[1][0];

    function textdb = PSYC.Text.FileTextDBFactoryFactory(text_db_path);

    PSYC.Storage.Factory storage = PSYC.Storage.FileFactory(data_path); 
    object debug = MMP.Utils.DebugManager();
    debug->set_default_backtrace(1);
    debug->set_default_debug(5);

    mapping config = ([
             "debug" : debug,
           "bind_to" : localaddr,
	   "storage" : storage,
      "create_local" : create_local,
     "offer_modules" : ({ "_compress" }),
    "deliver_remote" : deliver_remote,
    "module_factory" : create_module,
 "default_localhost" : hostname,
            "textdb" : textdb,
    "stille_duldung" : 1,
         "love_json" : 1,
  "primitive_client" : 1,
                     ]);

    if (localaddr && localaddr != hostname)
        config->localhosts = ({ localaddr });

    PSYC.Server root = PSYC.Server(config);
    port_obj->servers[conf] = root;

    werror("Psychaven %s ready: %s\n", hostname, Calendar.ISO.now()->format_smtp());
    return;
  }
}

void deliver_remote(MMP.Packet p, MMP.Uniform target) {
    
    switch (target->scheme) { 
    case "psyc":
	port_obj->servers[conf]->deliver_remote(p, target);	
	break;
    }
}

// does _not_ check whether the uni->host is local.
object create_local(mapping params) 
{
    werror("create_local(%O)\n", params);
    MMP.Uniform uni = params["uniform"];
    params += ([ "storage" : params["storage_factory"]->getStorage(uni),
		     ]);
    write("creating object for %O.\n", uni);
    object o;
    if (uni->resource && sizeof(uni->resource) > 1) 
    {
      switch (uni->resource[0]) 
      {
        case '~':
	{
          // TODO check for the path...
          o = PSYC.Person(params);
          mapping handler_params = params + ([ "parent" : o,
		                               "sendmmp" : o->sendmmp,
                                             ]);
	  o->add_handlers(
	        PSYC.Handler.Do(handler_params),
	        PSYCLocal.Person(handler_params),
	                 );
	}
        break;
        case '@':
	{
          o = PSYC.Place(params);
          mapping handler_params = params + ([ "parent" : o,
		                               "sendmmp" : o->sendmmp,
                                             ]);
	  o->add_handlers(PSYCLocal.Place(handler_params));
	}
        break;
      } 
    }
    else 
      o = PSYC.Root(params);

//    o->add_handlers( 
//	  PSYC.Handler.ClientFriendship(o, o->sendmmp, uni),
//	           );

    return o;
}

// we transmit the variables of the neg packet. i dont have a better idea
// right now
object create_module(string name, mapping vars) {

    switch (name) {
    case "_compress":
	
    case "_encrypt":

    }
}