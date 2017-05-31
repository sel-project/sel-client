module sel.client;

import std.datetime : Duration, dur;
import std.socket : Address, InternetAddress;

import sel.server : Server;

class Client {

	public immutable string name;

	public this(string name) {
		this.name = name;
	}

	public abstract pure nothrow @property @safe @nogc ushort defaultPort();

	public final const(Server) ping(Address address, Duration timeout=dur!"seconds"(5)) {
		return this.pingImpl(address, timeout);
	}

	public final const(Server) ping(string ip, ushort port, Duration timeout=dur!"seconds"(5)) {
		return this.ping(new InternetAddress(ip, port), timeout);
	}
	public final const(Server) ping(string ip, Duration timeout=dur!"seconds"(5)) {
		return this.ping(ip, this.defaultPort, timeout);
	}

	protected abstract Server pingImpl(Address address, Duration timeout);

}
