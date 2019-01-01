/*
 * Copyright (c) 2017-2019 sel-project
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 */
/**
 * Copyright: 2017-2019 sel-project
 * License: MIT
 * Authors: Kripth
 * Source: $(HTTP github.com/sel-project/sel-client/sel/client/client.d, sel/client/client.d)
 */
module sel.client.client;

import std.conv : to;
import std.datetime : Duration, dur;
import std.socket : Address, InternetAddress;

import sel.client.util : Server, IHandler;
import sel.net : Stream;

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

	/**
	 * Pings a server and returns the obtained data without parsing it.
	 * Example:
	 * ---
	 * assert(minecraft.rawPing("play.lbsg.net").startsWith("MCPE;"));
	 * assert(java.rawPing("mc.hypixel.net").startsWith("{")); // json
	 * ---
	 */
	public final string rawPing(Address address, Duration timeout=dur!"seconds"(5)) {
		return this.rawPingImpl(address, address.toAddrString(), to!ushort(address.toPortString()), timeout);
	}
	
	/// ditto
	public final string rawPing(string ip, ushort port, Duration timeout=dur!"seconds"(5)) {
		return this.rawPingImpl(new InternetAddress(ip, port), ip, port, timeout);
	}
	
	/// ditto
	public final string rawPing(string ip, Duration timeout=dur!"seconds"(5)) {
		return this.rawPing(ip, this.defaultPort, timeout);
	}

	protected abstract string rawPingImpl(Address address, string ip, ushort port, Duration timeout);

	public Stream connect(Address address, IHandler handler, Duration timeout=dur!"seconds"(5)) {
		return this.connectImpl(address, address.toAddrString(), to!ushort(address.toPortString()), timeout, handler);
	}

	public Stream connect(string ip, ushort port, IHandler handler, Duration timeout=dur!"seconds"(5)) {
		return this.connectImpl(new InternetAddress(ip, port), ip, port, timeout, handler);
	}

	public Stream connect(string ip, IHandler handler, Duration timeout=dur!"seconds"(5)) {
		return this.connect(ip, this.defaultPort, handler, timeout);
	}

	protected abstract Stream connectImpl(Address address, string ip, ushort port, Duration timeout, IHandler hanlder);

}
