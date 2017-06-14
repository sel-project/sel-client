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
module sel.client.query;

import std.bitmanip : nativeToBigEndian, peek;
import std.conv : to;
import std.datetime : StopWatch, dur;
import std.socket;
import std.string : indexOf, lastIndexOf, strip, split;
import std.system : Endian;

import sel.client.util : Server;

enum QueryType { basic,	full }

const(Query) query(Address address, QueryType type=QueryType.full) {
	Socket socket = new UdpSocket(address.addressFamily);
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(4));
	ubyte[] buffer = new ubyte[4096];
	ptrdiff_t recv;
	socket.sendTo(cast(ubyte[])[254, 253, 9, 0, 0, 0, 0], address);
	if((recv = socket.receiveFrom(buffer, address)) >= 7 && buffer[0..5] == [9, 0, 0, 0, 0] && buffer[recv-1] == 0) {
		StopWatch timer;
		timer.start();
		socket.sendTo(cast(ubyte[])[254, 253, 0, 0, 0, 0, 0] ~ nativeToBigEndian(to!int(cast(string)buffer[5..recv-1])) ~ new ubyte[type==QueryType.full?4:0], address);
		if((recv = socket.receiveFrom(buffer, address)) > 5 && buffer[0..5] == [0, 0, 0, 0, 0]) {
			timer.stop();
			size_t index = 5;
			string readString() {
				size_t next = index;
				while(next < buffer.length && buffer[next] != 0) next++;
				string ret = cast(string)buffer[index..next++].dup;
				index = next;
				return ret;
			}
			if(type == QueryType.basic) {
				string motd = readString();
				string gametype = readString();
				string map = readString();
				string online = readString();
				string max = readString();
				ushort port = peek!(ushort, Endian.littleEndian)(buffer, &index);
				string ip = readString();
				return Query(Server(motd, 0, to!int(online), to!int(max), timer.peek.msecs), ip, port, gametype, map);
			} else {
				string[string] data;
				string next;
				while((next = readString()).length) {
					data[next] = readString();
				}
				auto motd = "hostname" in data;
				auto gametype = "gametype" in data;
				auto map = "map" in data;
				auto online = "numplayers" in data;
				auto max = "maxplayers" in data;
				auto port = "hostport" in data;
				auto ip = "hostip" in data;
				if(motd && online && max && port && ip) {
					Query ret = Query(Server(*motd, 0, to!int(*online), to!int(*max), timer.peek.msecs), *ip, to!ushort(*port), gametype ? *gametype : "SMP", map ? *map : "");
					auto plugins = "plugins" in data;
					if(plugins) {
						ptrdiff_t i = indexOf(*plugins, ":");
						if(i == -1) {
							ret.software = strip(*plugins);
						} else {
							ret.software = strip((*plugins)[0..i]);
							foreach(plugin ; split((*plugins)[i+1..$], ";")) {
								i = plugin.lastIndexOf(" ");
								if(i == -1) {
									ret.plugins ~= Plugin(plugin.strip);
								} else {
									ret.plugins ~= Plugin(strip(plugin[0..i]), strip(plugin[i+1..$]));
								}
							}
						}
					}
					if(index + 10 < recv && buffer[index..index+10] == "\u0001player_\0\0") {
						index += 10;
						while((next = readString()).length) {
							ret.players ~= next;
						}
					}
					return ret;
				}
			}
		}
	}
	return Query.init;
}

/// ditto
const(Query) query(string ip, ushort port, QueryType type=QueryType.full) {
	return query(new InternetAddress(ip, port), type);
}

/// ditto
const(Query) javaQuery(string ip, QueryType type=QueryType.full) {
	return query(ip, ushort(25565), type);
}

/// ditto
const(Query) pocketQuery(string ip, QueryType type=QueryType.full) {
	return query(ip, ushort(19132), type);
}

struct Plugin {

	string name, version_;

}

struct Query {

	Server server;

	string ip;
	ushort port;

	string gametype;
	string map;

	string software;
	Plugin[] plugins;

	string[] players;

	public inout string toString() {
		if(this.server.valid) {
			return "Query(" ~ this.server.toString()[7..$-1] ~ ", ip: " ~ this.ip ~ ", port: " ~ to!string(this.port) ~ ", gametype: " ~ this.gametype ~ ", map: " ~ this.map ~ ")";
		} else {
			return "Query()";
		}
	}

	alias server this;

}
