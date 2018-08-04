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
 * Source: $(HTTP github.com/sel-project/sel-client/sel/client/bedrock.d, sel/client/bedrock.d)
 */
module sel.client.bedrock;

import std.conv : to, ConvException;
import std.datetime : Duration;
import std.datetime.stopwatch : StopWatch;
import std.random : uniform;
import std.socket : getAddress;
import std.string : split;

import libasync;

import sel.client.client : isSupported, Client, Connection;
import sel.client.util : Server, IHandler;

import xbuffer;

debug import std.stdio : writeln;

import Raknet = sel.raknet.packet;

class GenericBedrockClient : Client {
	
	public static string randomUsername() {
		enum char[] pool = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz ".dup;
		char[] ret = new char[uniform!"[]"(1, 15)];
		foreach(i, ref c; ret) {
			c = pool[uniform(0, (i==0 || i==ret.length-1 ? $-1 : $))];
		}
		return ret.idup;
	}
	
	public this(EventLoop eventLoop, string name) {
		super(eventLoop, name);
	}
	
	public this(EventLoop eventLoop) {
		this(eventLoop, randomUsername());
	}

	public this(string name) {
		this(getThreadEventLoop());
	}

	public this() {
		this(getThreadEventLoop());
	}
	
	public override pure nothrow @property @safe @nogc ushort defaultPort() {
		return ushort(19132);
	}
	
	protected override void pingImpl(string ip, ushort port, Duration timeout, void delegate(Server) callback) {
		StopWatch timer;
		timer.start();
		this.rawPingImpl(ip, port, timeout, (string str){
			if(str !is null) {
				string[] spl = str.split(";");
				if(spl.length >= 6 && spl[0] == "MCPE") {
					uint latency;
					timer.peek.split!"msecs"(latency);
					try {
						callback(Server(spl[1], to!uint(spl[2]), to!int(spl[4]), to!int(spl[5]), latency));
						return;
					} catch(ConvException) {}
				}
			}
			callback(Server.init);
		});
	}
	
	protected override void rawPingImpl(string ip, ushort port, Duration timeout, void delegate(string) callback) {

		bool success = false;

		NetworkAddress address = NetworkAddress(getAddress(ip, port)[0]);
		AsyncUDPSocket socket = new AsyncUDPSocket(this.eventLoop);

		AsyncTimer timer = new AsyncTimer(this.eventLoop);
		timer.duration = timeout;
		timer.run({
			if(!success) callback(null);
		});

		import std.stdio : writeln;

		writeln(address);

		void run(UDPEvent event) {
			if(event == UDPEvent.READ) {
				static ubyte[] buffer = new ubyte[512];
				NetworkAddress _address;
				socket.recvFrom(buffer, _address);
				if(address == _address) {
					if(buffer[0] == Raknet.UnconnectedPong.ID) {
						try {
							auto packet = new Raknet.UnconnectedPong();
							packet.autoDecode(buffer);
							success = true;
							callback(packet.status);
						} catch(BufferOverflowException) {}
					}
				}
			}
		}

		socket.host("0.0.0.0", port);
		socket.run(&run);

		socket.sendTo(new Raknet.UnconnectedPing(0, 0).autoEncode(), address);

	}
	
	protected override Connection connectImpl(string ip, ushort port, Duration timeout, IHandler handler) {
		/*ubyte[] buffer = new ubyte[2048];
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
		}*/
		return null;
	}
	
}

class BedrockClient(uint __protocol) : GenericBedrockClient if(isSupported!("bedrock", __protocol)) {
	
	mixin("import Play = soupply." ~ type!__protocol ~ to!string(__protocol) ~ ".protocol.play;");
	mixin("import Types = soupply." ~ type!__protocol ~ to!string(__protocol) ~ ".types;");
	
	alias Clientbound = FilterPackets!("CLIENTBOUND", Play.Packets);
	alias Serverbound = FilterPackets!("SERVERBOUND", Play.Packets);

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
