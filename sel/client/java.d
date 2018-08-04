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
 * Source: $(HTTP github.com/sel-project/sel-client/sel/client/java.d, sel/client/java.d)
 */
module sel.client.java;

import std.conv : to;
import std.datetime : Duration, dur;
import std.datetime.stopwatch : StopWatch;
import std.json : JSONValue, JSON_TYPE, parseJSON;
import std.net.curl : HTTP, post;
import std.random : uniform;
import std.socket : Socket, TcpSocket, SocketOptionLevel, SocketOption, Address;
import std.uuid : UUID, parseUUID;
import std.zlib : Compress, UnCompress;

import libasync : EventLoop, getThreadEventLoop, AsyncTCPConnection, TCPOption;

import sel.chat : parseChat;
import sel.client.client : isSupported, Client, Connection;
import sel.client.util : Server, IHandler;
import sel.stream : Stream, LengthPrefixedModifier, CompressedModifier;

import soupply.java.protocol.login_clientbound : Disconnect, LoginSuccess, SetCompression, EncryptionRequest;
import soupply.java.protocol.login_serverbound : LoginStart, EncryptionResponse;
import soupply.java.protocol.status : Handshake, Request, Response, Latency;

import xbuffer;

class GenericJavaClient : Client {
	
	public static string randomUsername() {
		enum char[] pool = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_".dup;
		char[] ret = new char[uniform!"[]"(3, 16)];
		foreach(ref c ; ret) {
			c = pool[uniform(0, $)];
		}
		return ret.idup;
	}

	public immutable uint protocol;
	
	private string accessToken;
	private UUID uuid;
	
	public this(EventLoop eventLoop, uint protocol, string name) {
		this.protocol = protocol;
		super(eventLoop, name);
	}
	
	public this(EventLoop eventLoop, uint protocol, string email, string password) {
		// authenticate user
		JSONValue[string] payload;
		payload["agent"] = ["name": JSONValue("Minecraft"), "version": JSONValue(1)];
		payload["username"] = email;
		payload["password"] = password;
		auto response = postJSON("https://authserver.mojang.com/authenticate", JSONValue(payload));
		if(response.type == JSON_TYPE.OBJECT) {
			auto at = "accessToken" in response;
			auto sp = "selectedProfile" in response;
			if(at && at.type == JSON_TYPE.STRING && sp && sp.type == JSON_TYPE.OBJECT) {
				this.accessToken = at.str;
				auto profile = (*sp).object;
				email = profile["name"].str;
				this.uuid = parseUUID(profile["id"].str);
			}
		}
		this(eventLoop, protocol, email);
	}
	
	public this(EventLoop eventLoop, uint protocol) {
		this(eventLoop, protocol, randomUsername());
	}
	
	public override pure nothrow @property @safe @nogc ushort defaultPort() {
		return ushort(25565);
	}
	
	protected override void pingImpl(string ip, ushort port, Duration timeout, void delegate(Server) callback) {

		Server ret;

		Buffer buffer = new Buffer(64);

		// setup connection
		Stream stream = new Stream(this.eventLoop, ip, port);
		stream.conn.setOption(TCPOption.TIMEOUT_RECV, timeout);
		stream.conn.setOption(TCPOption.TIMEOUT_SEND, timeout);
		stream.modify!(LengthPrefixedModifier!varuint)();

		stream.onConnect = {
			
			// handshake
			stream.send(new Handshake(this.protocol, ip, port, Handshake.STATUS).autoEncode());
			stream.send(new Request().autoEncode());

		};

		stream.onClose = { if(!ret.success) callback(ret); };

		// handle status response
		stream.handler = (Buffer buffer){
			if(buffer.canRead(1) && buffer.read!ubyte() == Response.ID) {
				Response response = new Response();
				response.decodeBody(buffer);
				auto json = parseJSON(response.json);
				if(json.type == JSON_TYPE.OBJECT) {
					auto description = "description" in json;
					auto version_ = "version" in json;
					auto players = "players" in json;
					auto favicon = "favicon" in json;
					if(description) {
						ret = Server(parseChat(*description), 0, 0, 0, 0);
					}
					if(players && players.type == JSON_TYPE.OBJECT) {
						auto online = "online" in *players;
						auto max = "max" in *players;
						if(online && online.type == JSON_TYPE.INTEGER && max && max.type == JSON_TYPE.INTEGER) {
							ret.online = cast(uint)online.integer;
							ret.max = cast(uint)max.integer;
						}
					}
					if(version_ && version_.type == JSON_TYPE.OBJECT) {
						auto protocol = "protocol" in *version_;
						if(protocol && protocol.type == JSON_TYPE.INTEGER) {
							ret.protocol = cast(uint)protocol.integer;
						}
					}
					if(favicon && favicon.type == JSON_TYPE.STRING) {
						ret.favicon = favicon.str;
					}
					// ping
					StopWatch timer;
					timer.start();
					buffer.reset();
					new Latency(0).encode(buffer);
					stream.send(buffer);
					stream.handler = (Buffer buffer){
						if(buffer.data.length == 9 && buffer.read!ubyte() == Latency.ID) {
							timer.stop();
							timer.peek.split!"msecs"(ret.ping);
						}
						ret.success = true;
						callback(ret);
					};
				}
			}
		};
		
	}
	
	protected override void rawPingImpl(string ip, ushort port, Duration timeout, void delegate(string) callback) {

		bool success = false;

		Buffer buffer = new Buffer(64);

		// setup stream
		Stream stream = new Stream(this.eventLoop, ip, port);
		stream.conn.setOption(TCPOption.TIMEOUT_RECV, timeout);
		stream.conn.setOption(TCPOption.TIMEOUT_SEND, timeout);
		stream.modify!(LengthPrefixedModifier!varuint)();

		stream.onConnect = {

			// handshake
			stream.send(new Handshake(this.protocol, ip, port, Handshake.STATUS).autoEncode());
			stream.send(new Request().autoEncode());
		
		};
		
		stream.onClose = { if(!success) callback(null); };

		// get response
		stream.handler = (Buffer buffer){
			if(buffer.canRead(1) && buffer.read!ubyte() == Response.ID) {
				try {
					Response response = new Response();
					response.decodeBody(buffer);
					success = true;
					callback(response.json);
				} catch(BufferOverflowException) {}
			}
		};

	}
	
	protected override Connection connectImpl(string ip, ushort port, Duration timeout, IHandler handler) {

		// setup buffer and stream
		Stream stream = new Stream(this.eventLoop, ip, port);
		//stream.conn.setOption(TCPOption.TIMEOUT_RECV, timeout);
		stream.conn.setOption(TCPOption.TIMEOUT_SEND, timeout);
		stream.modify!(LengthPrefixedModifier!varuint)();
		
		Connection conn = this.createConnection(stream);

		stream.onConnect = {

			// handshake and login
			stream.send(new Handshake(this.protocol, ip, port, Handshake.LOGIN).autoEncode());
			stream.send(new LoginStart(this.name).autoEncode());

		};

		//TODO
		stream.onClose = {

			conn.connected = false;
			if(conn.status == Connection.Status.joined) {
				//TODO change status
				conn.onClientLeft();
			}

		};

		import std.stdio;

		// login sequence
		bool delegate(Buffer)[ubyte] expected = [
			Disconnect.ID: (Buffer buffer){
				conn.status = Connection.Status.disconnected;
				conn.message = Disconnect.fromBuffer(buffer.data!ubyte).reason;
				return false;
			},
			EncryptionRequest.ID: (Buffer buffer){
				conn.status = Connection.Status.authRequired;
				return false;
			},
			SetCompression.ID: (Buffer buffer){
				stream.deleteModifiers();
				stream.modify!(CompressedModifier!varuint)(SetCompression.fromBuffer(buffer.data!ubyte).thresold);
				stream.modify!(LengthPrefixedModifier!varuint)();
				return true;
			}
		];
		Connection delegate(Buffer)* del;
		ubyte id;
		stream.handler = (Buffer buffer){
			ubyte id = buffer.peek!ubyte();
			auto del = id in expected;
			if(del) {
				if((*del)(buffer)) expected.remove(id);
				else return;
			} else if(id == LoginSuccess.ID) {
				auto ls = LoginSuccess.fromBuffer(buffer.data!ubyte);
				if(ls.username == this.name) {
					this.uuid = parseUUID(ls.uuid); //TODO may throw an exception
					//TODO set socket timeout to 0
					conn.status = Connection.Status.joined;
					conn.onClientJoin();
					this.startGameLoop(stream, conn, handler);
				}
			}
		};

		return conn;

	}

	protected void startGameLoop(Stream stream, Connection connection, IHandler handler) {
		connection.connected = false;
		connection.status = Connection.Status.unimplemented;
	}

	protected Connection createConnection(Stream stream) {
		return new Connection(Connection.Status.joining);
	}

}

class JavaClient(uint __protocol) : GenericJavaClient if(isSupported!("java", __protocol)) {

	mixin("import soupply.java" ~ to!string(__protocol) ~ ".packet : Packet = Java" ~ __protocol.to!string ~ "Packet;");

	static if(__protocol < 393) {
		mixin("public import Clientbound = soupply.java" ~ to!string(__protocol) ~ ".protocol.clientbound;");
		mixin("public import Serverbound = soupply.java" ~ to!string(__protocol) ~ ".protocol.serverbound;");
	} else {
		mixin("public import Clientbound = soupply.java" ~ to!string(__protocol) ~ ".protocol.play_clientbound;");
		mixin("public import Serverbound = soupply.java" ~ to!string(__protocol) ~ ".protocol.play_serverbound;");
	}
	
	public this(EventLoop eventLoop, string name) {
		super(eventLoop, __protocol, name);
	}

	public this(EventLoop eventLoop, string email, string password) {
		super(eventLoop, __protocol, email, password);
	}

	public this(EventLoop eventLoop) {
		super(eventLoop, __protocol);
	}

	public this(string name) {
		this(getThreadEventLoop(), name);
	}

	public this(string email, string password) {
		this(getThreadEventLoop(), email, password);
	}

	public this() {
		this(getThreadEventLoop());
	}
	
	protected override void startGameLoop(Stream stream, sel.client.client.Connection connection, IHandler handler) {
		stream.handler = (Buffer buffer){
			ubyte[] packet = buffer.data!ubyte;
			try switch(buffer.peek!ubyte()) {
				case Clientbound.KeepAlive.ID:
					import std.stdio : writeln;
					writeln("KEEP ALIVE");
					stream.send(new Serverbound.KeepAlive(Clientbound.KeepAlive.fromBuffer(packet).id).autoEncode());
					break;
				case Clientbound.Disconnect.ID:
					//TODO message
					connection.connected = false;
					connection.status = Connection.Status.disconnected;
					break;
				default:
					handler.handle(connection, packet);
					break;
			} catch(BufferOverflowException) {
				//TODO disconnected with wrong packet error
				connection.connected = false;
			}
		};
	}

	protected override sel.client.client.Connection createConnection(Stream stream) {
		return new Connection(stream);
	}

	static class Connection : sel.client.client.Connection {

		private Stream stream;

		this(Stream stream) {
			super(Status.joining);
			this.stream = stream;
		}

		public void send(Packet packet) {
			this.stream.send(packet.autoEncode());
		}

		public override void sendMessage(string message) {
			this.send(new Serverbound.ChatMessage(message));
		}

		public override void kill() {
			this.stream.conn.kill();
		}

	}
	
}

private JSONValue postJSON(string url, JSONValue json) {
	HTTP http = HTTP();
	http.addRequestHeader("Content-Type", "application/json");
	return parseJSON(post(url, json.toString(), http).idup);
}
