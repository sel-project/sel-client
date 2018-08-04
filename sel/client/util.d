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
 * Source: $(HTTP github.com/sel-project/sel-client/sel/client/util.d, sel/client/util.d)
 */
module sel.client.util;

import std.conv : to;
import std.regex : ctRegex, replaceAll;
import std.traits : Parameters;

import sel.client.client : Connection;
import sel.format : unformat;

import xbuffer : Buffer;

/**
 * Server's informations retrieved by a client's ping.
 */
struct Server {

	bool success = false;
	
	string motd;
	string rawMotd;
	
	uint protocol;
	int online, max;
	
	string favicon;
	
	ulong ping;
	
	public this(string motd, uint protocol, int online, int max, ulong ping) {
		this.success = true;
		this.motd = motd.unformat;
		this.rawMotd = motd;
		this.protocol = protocol;
		this.online = online;
		this.max = max;
		this.ping = ping;
	}
	
	public inout string toString() {
		if(this.success) {
			return "Server(motd: " ~ this.motd ~ ", protocol: " ~ to!string(this.protocol) ~ ", players: " ~ to!string(this.online) ~ "/" ~ to!string(this.max) ~ ", ping: " ~ to!string(this.ping) ~ " ms)";
		} else {
			return "Server()";
		}
	}

	alias success this;
	
}

interface IHandler {

	public void handle(Connection connection, ubyte[] buffer);

}

class Handler(E...) : IHandler { //TODO validate packets

	private E handlers;

	public this(E handlers) {
		this.handlers = handlers;
	}

	public override void handle(Connection connection, ubyte[] buffer) {
		this.handleImpl(connection, new Buffer(buffer));
	}

	private void handleImpl(Connection connection, Buffer buffer) {
		switch(buffer.peek!ubyte()) {
			foreach(i, F; E) {
				static if(is(typeof(Parameters!F[0].ID))) {
					case Parameters!F[0].ID: {
						alias Packet = Parameters!F[0];
						auto packet = new Packet();
						packet.decode(buffer);
						this.handlers[i](packet);
						return;
					}
				} else static if(Parameters!F.length == 2 && is(Parameters!F[0] : Connection) && is(typeof(Parameters!F[1].ID))) {
					case Parameters!F[1].ID: {
						alias Packet = Parameters!F[1];
						auto packet = new Packet();
						packet.decode(buffer);
						this.handlers[i](connection, packet);
						return;
					}
				}
			}
			default: break;
		}
	}

}

Handler!E handler(E...)(E handlers) {
	return new Handler!E(handlers);
}