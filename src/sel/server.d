module sel.server;

import std.conv : to;
import std.regex : ctRegex, replaceAll;

struct Server {

	string motd;
	string rawMotd;

	uint protocol;
	int online, max;

	ulong ping;

	public this(string motd, uint protocol, int online, int max, ulong ping) {
		this.motd = motd.replaceAll(ctRegex!"§[0-9a-fk-or]", "");
		this.rawMotd = motd;
		this.protocol = protocol;
		this.online = online;
		this.max = max;
		this.ping = ping;
	}

	public inout string toString() {
		return "Server(motd: " ~ this.motd ~ ", protocol: " ~ to!string(this.protocol) ~ ", players: " ~ to!string(this.online) ~ "/" ~ to!string(this.max) ~ ", ping: " ~ to!string(this.ping) ~ " ms)";
	}

}
