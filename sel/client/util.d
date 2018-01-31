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
 * License: LGPL-3.0
 * Authors: Kripth
 * Source: $(HTTP github.com/sel-project/sel-client/sel/client/util.d, sel/client/util.d)
 */
module sel.client.util;

import std.conv : to;
import std.regex : ctRegex, replaceAll;
import std.string : strip;
import std.traits : Parameters;

/**
 * Server's informations retrieved by a client's ping.
 */
struct Server {

	bool valid = false;
	
	string motd;
	string rawMotd;
	
	uint protocol;
	int online, max;
	
	string favicon;
	
	ulong ping;
	
	public this(string motd, uint protocol, int online, int max, ulong ping) {
		this.valid = true;
		this.motd = motd.replaceAll(ctRegex!"§[0-9a-fk-or]", "").strip;
		this.rawMotd = motd;
		this.protocol = protocol;
		this.online = online;
		this.max = max;
		this.ping = ping;
	}
	
	public inout string toString() {
		if(this.valid) {
			return "Server(motd: " ~ this.motd ~ ", protocol: " ~ to!string(this.protocol) ~ ", players: " ~ to!string(this.online) ~ "/" ~ to!string(this.max) ~ ", ping: " ~ to!string(this.ping) ~ " ms)";
		} else {
			return "Server()";
		}
	}

	alias valid this;
	
}

interface IHandler {

	public void handle(ubyte[] buffer);

}

class Handler(E...) : IHandler { //TODO validate packets

	private E handlers;

	public this(E handlers) {
		this.handlers = handlers;
	}

	public override void handle(ubyte[] buffer) {
		foreach(i, F; E) {
			static if(is(typeof(Parameters!F[0].ID))) {
				if(Parameters!F[0].ID == buffer[0]) {
					this.handlers[i](Parameters!F[0].fromBuffer(buffer));
				}
			} else static if(is(Parameters!F[0] : ubyte[])) {
				this.handlers[i](buffer);
			}
		}
	}

}

Handler!E handler(E...)(E handlers) {
	return new Handler!E(handlers);
}