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

import std.conv : to, ConvException;
import std.datetime : Duration, StopWatch;
import std.random : uniform;
import std.socket;
import std.string : split;

import sel.client.client : isSupported, Client;
import sel.client.util : Server, IHandler;
import sel.stream : Stream;

debug import std.stdio : writeln;

import RaknetTypes = sul.protocol.raknet8.types;
import Control = sul.protocol.raknet8.control;
import Encapsulated = sul.protocol.raknet8.encapsulated;
import Unconnected = sul.protocol.raknet8.unconnected;

enum __magic = cast(ubyte[16])x"00 FF FF 00 FE FE FE FE FD FD FD FD 12 34 56 78";

class RaknetStream : Stream {
	
	private Address address;
	private immutable size_t mtu;
	
	private ubyte[] buffer;
	
	private uint send_count = 0;
	
	public this(Socket socket, Address address, size_t mtu) {
		super(socket);
		this.address = address;
		this.mtu = mtu;
		this.buffer = new ubyte[mtu + 128];
	}
	
	public override ptrdiff_t send(ubyte[] buffer) {
		return this.sendRaknet(ubyte(254) ~ buffer);
	}
	
	public ptrdiff_t sendRaknet(ubyte[] buffer) {
		if(buffer.length > mtu) {
			writeln("buffer is too long!");
			return 0;
		} else {
			auto packet = new Control.Encapsulated(this.send_count, RaknetTypes.Encapsulation(64, cast(ushort)(buffer.length*8), this.send_count, 0, ubyte(0), RaknetTypes.Split.init, buffer));
			this.send_count++;
			return this.socket.sendTo(packet.encode(), this.address);
		}
	}
	
	public override ubyte[] receive() {
		auto recv = this.socket.receiveFrom(this.buffer, this.address);
		if(recv >= 0) {
			switch(this.buffer[0]) {
				case Control.Ack.ID:
					auto ack = Control.Ack.fromBuffer(this.buffer);
					//TODO remove from the waiting_ack queue
					return receive();
				case Control.Nack.ID:
					// unused
					return receive();
				case 128:..case 143:
					auto enc = Control.Encapsulated.fromBuffer(this.buffer[0..recv]);
					if(enc.encapsulation.info & 16) {
						//TODO handle splitted packets
						break;
					} else {
						writeln(enc.encapsulation.payload);
						return enc.encapsulation.payload;
					}
				default:
					break;
			}
		}
		return [];
	}
	
}

class MinecraftClient(uint __protocol) : Client if(isSupported!("pocket", __protocol)) {
	
	public static string randomUsername() {
		enum char[] pool = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz ".dup;
		char[] ret = new char[uniform!"[]"(1, 15)];
		foreach(ref c ; ret) {
			c = pool[uniform(0, $)];
		}
		return ret.idup;
	}
	
	mixin("import Play = sul.protocol.pocket" ~ to!string(__protocol) ~ ".play;");
	mixin("import Types = sul.protocol.pocket" ~ to!string(__protocol) ~ ".types;");
	
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
					stream.sendRaknet(new Encapsulated.ClientConnect(0, 0).encode());
					buffer = stream.receive();
					if(buffer.length && buffer[0] == Encapsulated.ServerHandshake.ID) {
						auto sh = Encapsulated.ServerHandshake.fromBuffer(buffer);
						stream.sendRaknet(new Encapsulated.ClientHandshake(sh.clientAddress, sh.systemAddresses, sh.pingId, 0).encode());
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
