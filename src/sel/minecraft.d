module sel.minecraft;

import std.conv : to;
import std.datetime : Duration, StopWatch;
import std.json;
import std.socket;

import sel.client : Client;
import sel.server : Server;

import sul.utils.var : varuint;

class MinecraftClient(uint __protocol) : Client {

	mixin("import Status = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".status;");
	mixin("import Login = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".login;");

	mixin("import Clientbound = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".clientbound;");
	mixin("import Serverbound = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".serverbound;");

	public this(string name) {
		super(name);
	}

	public override pure nothrow @property @safe @nogc ushort defaultPort() {
		return ushort(25565);
	}

	protected override Server pingImpl(Address address, string ip, ushort port, Duration timeout) {
		Socket socket = new TcpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		socket.connect(address);
		socket.blocking = true;
		// require status
		socket.send(addLength(new Status.Handshake(__protocol, ip, port, Status.Handshake.STATUS).encode()));
		socket.send(addLength(new Status.Request().encode()));
		ubyte[] packet = receive(socket);
		if(packet.length && packet[0] == Status.Response.ID) {
			auto json = parseJSON(Status.Response.fromBuffer(packet).json);
			if(json.type == JSON_TYPE.OBJECT) {
				Server server;
				auto description = "description" in json;
				auto version_ = "version" in json;
				auto players = "players" in json;
				auto favicon = "favicon" in json;
				if(description) {
					string desc = "";
					if(description.type == JSON_TYPE.STRING) { //TODO complex motds
						desc = description.str;
					} else if(description.type == JSON_TYPE.OBJECT) {
						auto text = "text" in *description;
						if(text && text.type == JSON_TYPE.STRING) {
							desc = text.str;
						}
					}
					server = Server(desc, 0, 0, 0, 0);
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
				socket.send(addLength(new Status.Latency(0).encode()));
				packet = receive(socket);
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

}

ubyte[] receive(Socket socket) {
	ubyte[] buffer = new ubyte[4096];
	ptrdiff_t recv = socket.receive(buffer);
	if(recv > 0) {
		size_t index = 0;
		size_t length = varuint.decode(buffer, &index);
		if(index <= recv && length > 0) {
			if(recv - index >= length) return buffer[index..recv];
			ubyte[] packet = buffer[index..recv].dup;
			length -= (recv - index);
			while(true) {
				recv = socket.receive(buffer);
				if(recv < 0) return [];
				packet ~= buffer[0..recv].dup;
				if(length <= recv) {
					return packet;
				} else {
					length -= recv;
				}
			}
		}
	}
	return [];
}

private ubyte[] addLength(ubyte[] buffer) {
	return varuint.encode(buffer.length.to!uint) ~ buffer;
}

unittest {

	auto minecraft = new MinecraftClient!316("unittest");

}
