module sel.client.pocket;

import std.conv : to;
import std.datetime : Duration, StopWatch;
import std.socket;
import std.string : split;

import sel.client.client : Client;
import sel.client.server : Server;

import RaknetTypes = sul.protocol.raknet8.types;
import Control = sul.protocol.raknet8.control;
import Encapsulated = sul.protocol.raknet8.encapsulated;
import Unconnected = sul.protocol.raknet8.unconnected;

enum ubyte[16] __magic = [0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34, 0x56, 0x78];

class PocketClient(uint __protocol) : Client {

	mixin("import Play = sul.protocol.pocket" ~ to!string(__protocol) ~ ".play;");
	mixin("import Types = sul.protocol.pocket" ~ to!string(__protocol) ~ ".types;");

	public this(string name) {
		super(name);
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

	protected override bool connectImpl(Address address, string ip, ushort port, Duration timeout) {
		return false;
	}

}

unittest {

	auto pocket = new PocketClient!112("unittest");

}
