/*
 * Copyright (c) 2017-2018 sel-project
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
 * Copyright: 2017-2018 sel-project
 * License: MIT
 * Authors: Kripth
 * Source: $(HTTP github.com/sel-project/sel-client/sel/client/client.d, sel/client/client.d)
 */
module sel.client.client;

import std.conv : to;
import std.datetime : Duration, dur;
import std.socket : Address, InternetAddress;

import libasync;

import sel.client.util : Server, IHandler;

/**
 * Indicates whether a protocol is supported for the given edition
 * of the game.
 * Example:
 * ---
 * assert(isSupported!("java", 393));
 * assert(!isSupported!("bedrock", 15));
 * ---
 */
enum isSupported(string type, uint protocol) = __traits(compiles, { mixin("import soupply." ~ type ~ to!string(protocol) ~ ";"); });

/**
 * Base class for a client that contains abstract ping and connection methods.
 */
class Client {

	private EventLoop _eventLoop;

	/**
	 * Client's username used to connect to the server.
	 */
	public immutable string name;

	public this(EventLoop eventLoop, string name) {
		_eventLoop = eventLoop;
		this.name = name;
	}

	/**
	 * Gets the client's event loop. It should be looped when using
	 * asynchronous methods, like asyncPing and connect.
	 * Example:
	 * ---
	 * client.eventLoop.loop();
	 * ---
	 */
	public final @property EventLoop eventLoop() pure nothrow @safe @nogc {
		return _eventLoop;
	}

	/**
	 * Gets the game's default port.
	 */
	public abstract @property ushort defaultPort() pure nothrow @safe @nogc;

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
	public final const(Server) ping(string ip, ushort port, Duration timeout=dur!"seconds"(5)) {
		bool done = false;
		Server server;
		this.asyncPing(ip, port, timeout, (Server s){
			done = true;
			server = s;
		});
		while(!done) this.eventLoop.loop();
		return server;
	}

	/// ditto
	public final const(Server) ping(string ip, Duration timeout=dur!"seconds"(5)) {
		return this.ping(ip, this.defaultPort, timeout);
	}

	/**
	 * Asynchrounously pings a server and calls the callback delegate when done.
	 * Example:
	 * ---
	 * client.asyncPing("example.com", (Server server){
	 *    writeln(server);
	 * });
	 * ---
	 */
	public final void asyncPing(string ip, ushort port, Duration timeout, void delegate(Server) callback) {
		this.pingImpl(ip, port, timeout, callback);
	}

	/// ditto
	public final void asyncPing(string ip, Duration timeout, void delegate(Server) callback) {
		this.asyncPing(ip, this.defaultPort, callback);
	}

	/// ditto
	public final void asyncPing(string ip, ushort port, void delegate(Server) callback) {
		this.asyncPing(ip, port, dur!"seconds"(5), callback);
	}

	/// ditto
	public final void asyncPing(string ip, void delegate(Server) callback) {
		this.asyncPing(ip, dur!"seconds"(5), callback);
	}

	protected abstract void pingImpl(string ip, ushort port, Duration timeout, void delegate(Server) callback);

	/**
	 * Pings a server and returns the obtained data without parsing it,
	 * or null on failure (not an empty string).
	 * Example:
	 * ---
	 * assert(minecraft.rawPing("play.lbsg.net").startsWith("MCPE;"));
	 * assert(java.rawPing("mc.hypixel.net").startsWith("{")); // json
	 * ---
	 */
	public final string rawPing(string ip, ushort port, Duration timeout=dur!"seconds"(5)) {
		bool done = false;
		string ret;
		this.asyncRawPing(ip, port, timeout, (string r){
			done = true;
			ret = r;
		});
		while(!done) this.eventLoop.loop();
		return ret;
	}
	
	/// ditto
	public final string rawPing(string ip, Duration timeout=dur!"seconds"(5)) {
		return this.rawPing(ip, this.defaultPort, timeout);
	}

	/**
	 * Asynchronously pings a server and calls the callback delegate when done.
	 * The result given in the callback is the same as the one given
	 * in the `rawPing` method.
	 */
	public final void asyncRawPing(string ip, ushort port, Duration timeout, void delegate(string) callback) {
		this.rawPingImpl(ip, port, timeout, callback);
	}

	/// ditto
	public final void asyncRawPing(string ip, Duration timeout, void delegate(string) callback) {
		this.asyncRawPing(ip, this.defaultPort, callback);
	}
	
	/// ditto
	public final void asyncRawPing(string ip, ushort port, void delegate(string) callback) {
		this.asyncRawPing(ip, port, dur!"seconds"(5), callback);
	}
	
	/// ditto
	public final void asyncRawPing(string ip, void delegate(string) callback) {
		this.asyncRawPing(ip, dur!"seconds"(5), callback);
	}

	protected abstract void rawPingImpl(string ip, ushort port, Duration timeout, void delegate(string) callback);

	/**
	 * Establishes an asynchronous connection between the client and the server.
	 * Example:
	 * ---
	 * Connection conn = client.connect("mc.example.com", handler());
	 * while(conn.connected) client.eventLoop.loop();
	 * ---
	 */
	public Connection connect(string ip, ushort port, IHandler handler, Duration timeout=dur!"seconds"(5)) {
		return this.connectImpl(ip, port, timeout, handler);
	}

	/// ditto
	public Connection connect(string ip, IHandler handler, Duration timeout=dur!"seconds"(5)) {
		return this.connect(ip, this.defaultPort, handler, timeout);
	}

	protected abstract Connection connectImpl(string ip, ushort port, Duration timeout, IHandler hanlder);

}

/**
 * Representation of a connection started with the client's connect method.
 */
class Connection {

	enum Status {

		joining,
		joined,
		unimplemented,
		disconnected,
		authRequired,

	}

	/**
	 * Indicates whether the client has still an open connection
	 * with the server.
	 */
	bool connected = true;

	/**
	 * Indicates the status of the connection or the result of
	 * the connection.
	 */
	Status status;
	string message;

	void delegate() onClientJoin, onClientLeft;

	this(Status status, string message="") {
		this.status = status;
		this.message = message;
		this.onClientJoin = {};
		this.onClientLeft = {};
	}

	/**
	 * Sends a text message to the server.
	 */
	public void sendMessage(string message) {}

	/**
	 * Stops the connection.
	 */
	public void kill() {}

}
