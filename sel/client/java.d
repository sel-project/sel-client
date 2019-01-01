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

import sel.client.client : isSupported, Client;
import sel.client.util : Server, IHandler;
import sel.net : Stream, TcpStream, ModifierStream, LengthPrefixedStream, CompressedStream;

import sul.utils.var : varuint;

debug import std.stdio : writeln;

class JavaClient(uint __protocol) : Client if(isSupported!("java", __protocol)) {
	
	public static string randomUsername() {
		enum char[] pool = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_".dup;
		char[] ret = new char[uniform!"[]"(3, 16)];
		foreach(ref c ; ret) {
			c = pool[uniform(0, $)];
		}
		return ret.idup;
	}
	
	mixin("import Status = sul.protocol.java" ~ to!string(__protocol) ~ ".status;");
	mixin("import Login = sul.protocol.java" ~ to!string(__protocol) ~ ".login;");
	
	mixin("public import Clientbound = sul.protocol.java" ~ to!string(__protocol) ~ ".clientbound;");
	mixin("public import Serverbound = sul.protocol.java" ~ to!string(__protocol) ~ ".serverbound;");
	
	private string _lasterror;
	
	private string accessToken;
	private UUID uuid;
	
	public this(string name) {
		super(name);
	}
	
	public this(string email, string password) {
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
		this(email);
	}
	
	public this() {
		this(randomUsername());
	}
	
	public override pure nothrow @property @safe @nogc ushort defaultPort() {
		return ushort(25565);
	}
	
	public final pure nothrow @property @safe @nogc string lastError() {
		return this._lasterror;
	}
	
	protected override Server pingImpl(Address address, string ip, ushort port, Duration timeout) {
		Socket socket = new TcpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		socket.connect(address);
		socket.blocking = true;
		auto stream = new LengthPrefixedStream!varuint(new TcpStream(socket));
		// require status
		stream.send(new Status.Handshake(__protocol, ip, port, Status.Handshake.STATUS).encode());
		stream.send(new Status.Request().encode());
		ubyte[] packet = stream.receive();
		if(packet.length && packet[0] == Status.Response.ID) {
			auto json = parseJSON(Status.Response.fromBuffer(packet).json);
			if(json.type == JSON_TYPE.OBJECT) {
				Server server;
				auto description = "description" in json;
				auto version_ = "version" in json;
				auto players = "players" in json;
				auto favicon = "favicon" in json;
				if(description) {
					server = Server(chatToString(*description), 0, 0, 0, 0);
				}
				if(players && players.type == JSON_TYPE.OBJECT) {
					auto online = "online" in *players;
					auto max = "max" in *players;
					if(online && online.type == JSON_TYPE.INTEGER && max && max.type == JSON_TYPE.INTEGER) {
						server.online = cast(uint)online.integer;
						server.max = cast(uint)max.integer;
					}
				}
				if(version_ && version_.type == JSON_TYPE.OBJECT) {
					auto protocol = "protocol" in *version_;
					if(protocol && protocol.type == JSON_TYPE.INTEGER) {
						server.protocol = cast(uint)protocol.integer;
					}
				}
				if(favicon && favicon.type == JSON_TYPE.STRING) {
					server.favicon = favicon.str;
				}
				// ping
				StopWatch timer;
				timer.start();
				stream.send(new Status.Latency(0).encode());
				packet = stream.receive();
				if(packet.length == 9 && packet[0] == Status.Latency.ID) {
					timer.stop();
					timer.peek.split!"msecs"(server.ping);
					socket.close();
					return server;
				}
			}
		}
		socket.close();
		return Server.init;
	}
	
	protected override string rawPingImpl(Address address, string ip, ushort port, Duration timeout) {
		Socket socket = new TcpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		socket.connect(address);
		socket.blocking = true;
		auto stream = new LengthPrefixedStream!varuint(new TcpStream(socket));
		// require status
		stream.send(new Status.Handshake(__protocol, ip, port, Status.Handshake.STATUS).encode());
		stream.send(new Status.Request().encode());
		ubyte[] packet = stream.receive();
		socket.close();
		if(packet.length && packet[0] == Status.Response.ID) {
			return Status.Response.fromBuffer(packet).json;
		} else {
			return "";
		}
	}
	
	protected override Stream connectImpl(Address address, string ip, ushort port, Duration timeout, IHandler handler) {
		Socket socket = new TcpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		socket.connect(address);
		socket.blocking = true;
		Stream stream = new LengthPrefixedStream!varuint(new TcpStream(socket));
		// handshake
		stream.send(new Status.Handshake(__protocol, ip, port, Status.Handshake.LOGIN).encode());
		stream.send(new Login.LoginStart(this.name).encode());
		//
		bool delegate(ubyte[])[ubyte] expected = [
			Login.Disconnect.ID: (ubyte[] buffer){
				this._lasterror = "Disconnected: " ~ chatToString(parseJSON(Login.Disconnect.fromBuffer!false(buffer).reason));
				return false;
			},
			Login.EncryptionRequest.ID: (ubyte[] buffer){
				this._lasterror = "Authentication required";
				return false;
			},
			Login.SetCompression.ID: (ubyte[] buffer){
				stream = new CompressedStream!varuint(stream, Login.SetCompression.fromBuffer!false(buffer).thresold);
				return true;
			}
		];
		ubyte[] buffer;
		do {
			buffer = stream.receive();
			if(buffer.length) {
				auto del = buffer[0] in expected;
				if(del) {
					(*del)(buffer[1..$]);
					expected.remove(buffer[0]);
				} else {
					break;
				}
			} else {
				this._lasterror = "Unexpected empty packet";
			}
		} while(buffer.length);
		if(buffer[0] == Login.LoginSuccess.ID) {
			auto ls = Login.LoginSuccess.fromBuffer(buffer);
			if(ls.username == this.name) {
				this.uuid = parseUUID(ls.uuid); //TODO may throw an exception
				import std.concurrency;
				spawn(&startGameLoop, cast(shared)stream, cast(shared)handler);
				return stream;
			} else {
				this._lasterror = "Username mismatch (" ~ this.name ~ " != " ~ ls.username ~ ")";
			}
		} else {
			this._lasterror = "Unexpected packet " ~ to!string(buffer[0]) ~ " when expecting " ~ to!string(expected.keys)[1..$-1];
		}
		socket.close();
		return null;
	}
	
	private static void startGameLoop(shared Stream _stream, shared IHandler _handler) {
		auto stream = cast()_stream;
		auto handler = cast()_handler;
		stream.socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"msecs"(0)); // connection is closed when socket is
		while(true) {
			auto packet = stream.receive();
			if(packet.length) {
				if(packet[0] == Clientbound.KeepAlive.ID) {
					stream.send(new Serverbound.KeepAlive(Clientbound.KeepAlive.fromBuffer(packet).id).encode());
				} else {
					handler.handle(packet);
					if(packet[0] == Clientbound.Disconnect.ID) {
						break;
					}
				}
			} else {
				// socket closed or packet with length 0
				break;
			}
		}
	}
	
}

private JSONValue postJSON(string url, JSONValue json) {
	HTTP http = HTTP();
	http.addRequestHeader("Content-Type", "application/json");
	return parseJSON(post(url, json.toString(), http).idup);
}

private string chatToString(JSONValue json) {
	if(json.type == JSON_TYPE.OBJECT) {
		string ret;
		auto text = "text" in json;
		if(text && text.type == JSON_TYPE.STRING) {
			ret ~= text.str;
		}
		auto extra = "extra" in json;
		if(extra && extra.type == JSON_TYPE.ARRAY) {
			foreach(element ; extra.array) {
				if(element.type == JSON_TYPE.OBJECT) {
					ret ~= chatToString(element);
				}
			}
		}
		return ret;
	} else if(json.type == JSON_TYPE.STRING) {
		return json.str;
	}
	return "";
}
