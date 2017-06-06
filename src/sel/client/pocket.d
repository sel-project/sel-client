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
module sel.client.pocket;

import std.conv : to;
import std.datetime : Duration, StopWatch;
import std.random : uniform;
import std.socket;
import std.string : split;

import sel.client.client : isSupported, Client;
import sel.client.stream : Stream;
import sel.client.util : Server, IHandler;

import RaknetTypes = sul.protocol.raknet8.types;
import Control = sul.protocol.raknet8.control;
import Encapsulated = sul.protocol.raknet8.encapsulated;
import Unconnected = sul.protocol.raknet8.unconnected;

enum ubyte[16] __magic = [0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34, 0x56, 0x78];

class PocketClient(uint __protocol) : Client if(isSupported!("pocket", __protocol)) {

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
		Socket socket = new UdpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		StopWatch timer;
		timer.start();
		socket.sendTo(new Unconnected.Ping(0, __magic, 0).encode(), address);
		ubyte[] buffer = new ubyte[512];
		if(socket.receiveFrom(buffer, address) > 0 && buffer[0] == Unconnected.Pong.ID) {
			timer.stop();
			auto spl = Unconnected.Pong.fromBuffer(buffer).status.split(";");
			if(spl.length >= 6 && spl[0] == "MCPE") {
				return Server(spl[1], to!uint(spl[2]), to!int(spl[4]), to!int(spl[5]), timer.peek.msecs);
			}
		}
		return Server.init;
	}

	protected override Stream connectImpl(Address address, string ip, ushort port, Duration timeout, IHandler handler) {
		return null;
	}

}

unittest {

	auto pocket = new PocketClient!112("unittest");

}
