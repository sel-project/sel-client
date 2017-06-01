module sel.client.minecraft;

import std.conv : to;
import std.datetime : Duration, StopWatch;
import std.json;
import std.random : uniform;
import std.socket;
import std.uuid : UUID, parseUUID;
import std.zlib : UnCompress;

import sel.client.client : Client;
import sel.client.server : Server;

import sul.utils.var : varuint;

import std.stdio : writeln;

class MinecraftClient(uint __protocol) : Client {

	public static string randomUsername() {
		enum char[] pool = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_".dup;
		char[] ret = new char[uniform!"[]"(3, 16)];
		foreach(ref c ; ret) {
			c = pool[uniform(0, $)];
		}
		return ret.idup;
	}

	mixin("import Status = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".status;");
	mixin("import Login = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".login;");

	mixin("import Clientbound = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".clientbound;");
	mixin("import Serverbound = sul.protocol.minecraft" ~ to!string(__protocol) ~ ".serverbound;");

	private string _lasterror;

	private size_t compressionThresold;

	private UUID uuid;

	public this(string name) {
		super(name);
	}

	public this() {
		this(randomUsername());
	}

	public override pure nothrow @property @safe @nogc ushort defaultPort() {
		return ushort(25565);
	}

	public final pure nothrow @property @safe @nogc string lastError() {
		return this._lasterror;
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
					server = Server(chatToString(*description), 0, 0, 0, 0);
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

	protected override bool connectImpl(Address address, string ip, ushort port, Duration timeout) {
		Socket socket = new TcpSocket(address.addressFamily);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeout);
		socket.connect(address);
		socket.blocking = true;
		// handshake
		socket.send(addLength(new Status.Handshake(__protocol, ip, port, Status.Handshake.LOGIN).encode()));
		socket.send(addLength(new Login.LoginStart(this.name).encode()));
		ubyte[] packet = receive(socket);
		if(packet.length) {
			if(packet[0] == Login.EncryptionRequest.ID) {
				this._lasterror = "Encryption required";
			} else if(packet[0] == Login.SetCompression.ID) {
				this.compressionThresold = Login.SetCompression.fromBuffer(packet).thresold;
				packet = receiveCompressed(socket);
				if(packet.length) {
					if(packet[0] == Login.Disconnect.ID) {
						this._lasterror = "Disconnected: " ~ chatToString(parseJSON(Login.Disconnect.fromBuffer(packet).reason));
					} else if(packet[0] == Login.LoginSuccess.ID) {
						auto ls = Login.LoginSuccess.fromBuffer(packet);
						if(ls.username == this.name) {
							this.uuid = parseUUID(ls.uuid);
							this.startGameLoop(socket);
							return true;
						} else {
							this._lasterror = "Username mismatch";
						}
					} else {
						with(Login) this._lasterror = "Unexpected packet: " ~ to!string(packet[0]) ~ " when expecting " ~ to!string(Disconnect.ID) ~ " or " ~ to!string(LoginSuccess.ID);
					}
				}
			}
		}
		socket.close();
		return false;
	}

	private void startGameLoop(Socket socket) {
		while(true) {
			auto packet = receiveCompressed(socket);
			if(packet.length) {
				if(packet[0] == Clientbound.KeepAlive.ID) {
					socket.send(addLength([ubyte.init] ~ new Serverbound.KeepAlive(Clientbound.KeepAlive.fromBuffer(packet).id).encode()));
				} else {
					//TODO call handler
				}
			} else {
				//TODO detect closed connection
			}
		}
	}

	class Connection {

		private Socket socket;

		public this(Socket socket) {
			this.socket = socket;
		}

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
					if(length != recv) {
						writeln("too much bytes! ", recv - length, " too much");
					}
					return packet;
				} else {
					length -= recv;
				}
			}
		}
	}
	return [];
}

ubyte[] receiveCompressed(Socket socket) {
	ubyte[] packet = receive(socket);
	if(packet.length) {
		if(packet[0] == 0) {
			return packet[1..$];

		} else {
			size_t length = varuint.fromBuffer(packet);
			auto uc = new UnCompress(length);
			packet = cast(ubyte[])uc.uncompress(packet.dup);
			packet ~= cast(ubyte[])uc.flush();
			return packet;
		}
	}
	return [];
}

private ubyte[] addLength(ubyte[] buffer) {
	return varuint.encode(buffer.length.to!uint) ~ buffer;
}

private string chatToString(JSONValue json) {
	if(json.type == JSON_TYPE.OBJECT) {
		auto text = "text" in json;
		if(text && text.type == JSON_TYPE.STRING) {
			return text.str;
		}
	} else if(json.type == JSON_TYPE.STRING) {
		return json.str;
	}
	return "";
}

unittest {

	auto minecraft = new MinecraftClient!316("unittest");

}
