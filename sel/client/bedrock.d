/*
 * Copyright (c) 2017-2018 SEL
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
/**
 * Copyright: 2017-2018 sel-project
 * License: MIT
 * Authors: Kripth
 * Source: $(HTTP github.com/sel-project/sel-client/sel/client/bedrock.d, sel/client/bedrock.d)
 */
module sel.client.bedrock;

import std.conv : to, ConvException;
import std.datetime : Duration, StopWatch;
import std.random : uniform;
import std.socket;
import std.string : split;

import sel.client.client : isSupported, Client;
import sel.client.util : Server, IHandler;
import sel.net : Stream, RaknetStream;

debug import std.stdio : writeln;

import RaknetTypes = sul.protocol.raknet8.types;
import Control = sul.protocol.raknet8.control;
import Encapsulated = sul.protocol.raknet8.encapsulated;
import Unconnected = sul.protocol.raknet8.unconnected;

enum __magic = cast(ubyte[16])x"00 FF FF 00 FE FE FE FE FD FD FD FD 12 34 56 78";

enum type(uint protocol) = protocol < 120 ? "pocket" : "bedrock";

class BedrockClient(uint __protocol) : Client if(isSupported!(type!__protocol, __protocol)) {
	
	public static string randomUsername() {
		enum char[] pool = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz ".dup;
		char[] ret = new char[uniform!"[]"(1, 15)];
		foreach(i, ref c; ret) {
			c = pool[uniform(0, (i==0 || i==ret.length-1 ? $-1 : $))];
		}
		return ret.idup;
	}
	
	mixin("import Play = sul.protocol." ~ type!__protocol ~ to!string(__protocol) ~ ".play;");
	mixin("import Types = sul.protocol." ~ type!__protocol ~ to!string(__protocol) ~ ".types;");
	
	alias Clientbound = FilterPackets!("CLIENTBOUND", Play.Packets);
	alias Serverbound = FilterPackets!("SERVERBOUND", Play.Packets);
	
	public this(string name) {
		super(name);
	}
	
	public this() {
		this(randomUsername());
	}
	
	public override pure nothrow @property @safe @nogc ushort defaultPort() {
		return ushort(19132);
	}
	
	protected override Server pingImpl(Address address, string ip, ushort port, Duration timeout) {
		StopWatch timer;
		timer.start();
		auto spl = this.rawPingImpl(address, ip, port, timeout).split(";");
		if(spl.length >= 6 && spl[0] == "MCPE") {
			try {
				return Server(spl[1], to!uint(spl[2]), to!int(spl[4]), to!int(spl[5]), timer.peek.msecs);
			} catch(ConvException) {}
		}
		return Server.init;
	}
	
	protected override string rawPingImpl(Address address, string ip, ushort port, Duration timeout) {
		Socket socket = new UdpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		socket.sendTo(new Unconnected.Ping(0, __magic, 0).encode(), address);
		ubyte[] buffer = new ubyte[512];
		if(socket.receiveFrom(buffer, address) > 0 && buffer[0] == Unconnected.Pong.ID) {
			return Unconnected.Pong.fromBuffer(buffer).status;
		} else {
			return "";
		}
	}
	
	protected override Stream connectImpl(Address address, string ip, ushort port, Duration timeout, IHandler handler) {
		ubyte[] buffer = new ubyte[2048];
		ptrdiff_t recv;
		Socket socket = new UdpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		foreach(mtu ; [2000, 1700, 1400, 1000, 500, 500]) {
			socket.sendTo(new Unconnected.OpenConnectionRequest1(__magic, 8, new ubyte[mtu]).encode(), address);
		}
		recv = socket.receiveFrom(buffer, address);
		if(recv > 0 && buffer[0] == Unconnected.OpenConnectionReply1.ID) {
			auto reply1 = Unconnected.OpenConnectionReply1.fromBuffer(buffer);
			if(reply1.mtuLength <= 2000 && reply1.mtuLength >= 500) {
				buffer = new ubyte[reply1.mtuLength + 100];
				socket.sendTo(new Unconnected.OpenConnectionRequest2(__magic, RaknetTypes.Address.init, reply1.mtuLength, 0).encode(), address);
				do {
					recv = socket.receiveFrom(buffer, address);
				} while(recv > 0 && buffer[0] != Unconnected.OpenConnectionReply2.ID);
				if(recv > 0) {
					auto reply2 = Unconnected.OpenConnectionReply2.fromBuffer(buffer);
					writeln(reply2);
					// start encapsulation
					auto stream = new RaknetStream(socket, address, reply1.mtuLength);
					stream.send(new Encapsulated.ClientConnect(0, 0).encode());
					buffer = stream.receive();
					if(buffer.length && buffer[0] == Encapsulated.ServerHandshake.ID) {
						auto sh = Encapsulated.ServerHandshake.fromBuffer(buffer);
						stream.send(new Encapsulated.ClientHandshake(sh.clientAddress, sh.systemAddresses, sh.pingId, 0).encode());
						// start new tick-based thread
						{
							bool connected = true;
							while(connected) {
								//TODO receive from other thread
								//TODO receive from socket (and do ack/nack, split management, handlers call)
								//TODO flush packets (queued from send method)
								//TODO wait ~50 ms
							}
						}
					}
				}
			}
		}
		return null;
	}
	
}

private struct FilterPackets(string property, E...) {
	@disable this();
	alias F = FilterPacketsImpl!(property, 0, E);
	mixin((){
			string ret;
			foreach(i, P; F) {
				ret ~= "alias " ~ P.stringof ~ "=F[" ~ to!string(i) ~ "];";
			}
			return ret;
		}());
}

private template FilterPacketsImpl(string property, size_t index, E...) {
	static if(index < E.length) {
		static if(mixin("E[index]." ~ property)) {
			alias FilterPacketsImpl = FilterPacketsImpl!(property, index+1, E);
		} else {
			alias FilterPacketsImpl = FilterPacketsImpl!(property, index, E[0..index], E[index+1..$]);
		}
	} else {
		alias FilterPacketsImpl = E;
	}
}
