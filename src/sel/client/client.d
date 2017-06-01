module sel.client.client;

import std.conv : to;
import std.datetime : Duration, dur;
import std.socket : Address, InternetAddress;

import sel.client.util : Server;

enum isSupported(string type, uint protocol) = __traits(compiles, { mixin("import sul.attributes." ~ type ~ to!string(protocol) ~ ";"); });

class Client {

	/**
	 * Client's username used to connect to the server.
	 */
	public immutable string name;

	public this(string name) {
		this.name = name;
	}

	/**
	 * Gets the game's default port.
	 */
	public abstract pure nothrow @property @safe @nogc ushort defaultPort();

	/**
	 * Pings a server to retrieve basic informations like MOTD, protocol used
	 * and online players.
	 * Returns: a Server struct with the server's informations or an empty one on failure
	 * Example:
	 * ---
	 * client.ping("127.0.0.1");
	 * client.ping("mc.hypixel.net", 25565);
	 * client.ping("localhost", dur!"seconds"(1));
	 * ---
	 */
	public final const(Server) ping(Address address, Duration timeout=dur!"seconds"(5)) {
		return this.pingImpl(address, address.toAddrString(), to!ushort(address.toPortString()), timeout);
	}

	/// ditto
	public final const(Server) ping(string ip, ushort port, Duration timeout=dur!"seconds"(5)) {
		return this.pingImpl(new InternetAddress(ip, port), ip, port, timeout);
	}

	/// ditto
	public final const(Server) ping(string ip, Duration timeout=dur!"seconds"(5)) {
		return this.ping(ip, this.defaultPort, timeout);
	}

	protected abstract Server pingImpl(Address address, string ip, ushort port, Duration timeout);

	public bool connect(Address address, Duration timeout=dur!"seconds"(5)) {
		return this.connectImpl(address, address.toAddrString(), to!ushort(address.toPortString()), timeout);
	}

	public bool connect(string ip, ushort port, Duration timeout=dur!"seconds"(5)) {
		return this.connectImpl(new InternetAddress(ip, port), ip, port, timeout);
	}

	public bool connect(string ip, Duration timeout=dur!"seconds"(5)) {
		return this.connect(ip, this.defaultPort, timeout);
	}

	protected abstract bool connectImpl(Address address, string ip, ushort port, Duration timeout);

}
