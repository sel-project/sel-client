/*
 * Copyright (c) 2017 SEL
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU Lesser General Public License for more details.
 * 
 */
module sel.client.minecraft;

import std.conv : to;
import std.datetime : Duration, StopWatch, dur;
import std.json : JSONValue, JSON_TYPE, parseJSON;
import std.net.curl : HTTP, post;
import std.random : uniform;
import std.socket;
import std.uuid : UUID, parseUUID;
import std.zlib : Compress, UnCompress;

import sel.client.client : isSupported, Client;
import sel.client.stream : Stream, LengthStream;
import sel.client.util : Server, IHandler;

import sul.utils.var : varuint;

import std.stdio : writeln;

private alias MinecraftStream = LengthStream!varuint;

private class MinecraftCompressionStream : MinecraftStream {

	private immutable size_t thresold;

	public this(Socket socket, size_t thresold) {
		super(socket);
		this.thresold = thresold;
	}

	public override ptrdiff_t send(ubyte[] buffer) {
		if(buffer.length >= this.thresold) {
			auto compress = new Compress();
			auto data = compress.compress(buffer);
			data ~= compress.flush();
			buffer = varuint.encode(buffer.length.to!uint) ~ cast(ubyte[])data;
		} else {
			buffer = ubyte.init ~ buffer;
		}
		return super.send(buffer);
	}

	public override ubyte[] receive() {
		ubyte[] buffer = super.receive();
		uint length = varuint.fromBuffer(buffer);
		if(length != 0) {
			// compressed
			//TODO add an option to disable compression or discard compressed packets
			auto uncompress = new UnCompress(length);
			buffer = cast(ubyte[])uncompress.uncompress(buffer.dup);
			buffer ~= cast(ubyte[])uncompress.flush();
		}
		return buffer;
	}

}

class MinecraftClient(uint __protocol) : Client if(isSupported!("minecraft", __protocol)) {

	public static string randomUsername() {
		enum char[] pool = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_".dup;
		char[] ret = new char[uniform!"[]"(3, 16)];
		foreach(ref c ; ret) {
			c = pool[uniform(0, $)];
		}
		return ret.idup;
	}

	mixin("import Status = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".status;");
	mixin("import Login = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".login;");

	mixin("public import Clientbound = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".clientbound;");
	mixin("public import Serverbound = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".serverbound;");

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
		MinecraftStream stream = new MinecraftStream(socket);
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
					server.ping = timer.peek.msecs;
					socket.close();
					return server;
				}
			}
		}
		socket.close();
		return Server.init;
	}

	protected override Stream connectImpl(Address address, string ip, ushort port, Duration timeout, IHandler handler) {
		Socket socket = new TcpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		socket.connect(address);
		socket.blocking = true;
		MinecraftStream stream = new MinecraftStream(socket);
		// handshake
		stream.send(new Status.Handshake(__protocol, ip, port, Status.Handshake.LOGIN).encode());
		stream.send(new Login.LoginStart(this.name).encode());
		ubyte[] packet = stream.receive();
		if(packet.length) {
			if(packet[0] == Login.EncryptionRequest.ID) {
				if(this.accessToken.length) {
					//TODO create shared secret and do auth request to sessionserver
				}
				writeln(Login.EncryptionRequest.fromBuffer(packet));
				this._lasterror = "Encryption required";
			} else if(packet[0] == Login.SetCompression.ID) {
				stream = new MinecraftCompressionStream(socket, Login.SetCompression.fromBuffer(packet).thresold);
				packet = stream.receive();
				if(packet.length) {
					if(packet[0] == Login.Disconnect.ID) {
						this._lasterror = "Disconnected: " ~ chatToString(parseJSON(Login.Disconnect.fromBuffer(packet).reason));
					} else if(packet[0] == Login.LoginSuccess.ID) {
						auto ls = Login.LoginSuccess.fromBuffer(packet);
						if(ls.username == this.name) {
							this.uuid = parseUUID(ls.uuid);
							import std.concurrency;
							spawn(&startGameLoop, cast(shared)stream, cast(shared)handler);
							return stream;
						} else {
							this._lasterror = "Username mismatch";
						}
					} else {
						with(Login) this._lasterror = "Unexpected packet: " ~ to!string(packet[0]) ~ " when expecting " ~ to!string(Disconnect.ID) ~ " or " ~ to!string(LoginSuccess.ID);
					}
				}
			}
		}
		socket.close();
		return null;
	}

	private static void startGameLoop(shared MinecraftStream _stream, shared IHandler _handler) {
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
				}
			} else {
				// socket closed or packet with length 0
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
		auto text = "text" in json;
		if(text && text.type == JSON_TYPE.STRING) {
			return text.str;
		}
	} else if(json.type == JSON_TYPE.STRING) {
		return json.str;
	}
	return "";
}

unittest {

	auto minecraft = new MinecraftClient!316("unittest");

}
