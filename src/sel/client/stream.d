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
module sel.client.stream;

import std.bitmanip : _write = write, _read = read;
import std.conv : to;
import std.socket : Socket;
import std.traits : isNumeric, isIntegral, Parameters;

class Stream {

	public Socket socket;

	public abstract ptrdiff_t send(ubyte[] buffer);

	public abstract ubyte[] receive();

}

class LengthStream(T) : Stream if(isNumeric!T || (is(typeof(T.encode)) && isIntegral!(Parameters!(T.encode)[0]))) {
	
	static if(isNumeric!T) {
		enum requiredSize = T.sizeof;
	} else {
		enum requiredSize = 1;
	}
	
	public Socket socket;
	
	private ubyte[] buffer;
	private ubyte[] next;
	private size_t nextLength = 0;
	
	public this(Socket socket, size_t bufferSize=4096) {
		this.socket = socket;
		this.buffer = new ubyte[bufferSize];
	}
	
	/**
	 * Sends a buffer prefixing it with its length.
	 * Returns: the number of bytes sent
	 */
	public override ptrdiff_t send(ubyte[] payload) {
		static if(isNumeric!T) {
			payload = new ubyte[T.length] ~ payload;
			_write(payload.length.to!T, payload, 0);
		} else {
			payload = T.encode(payload.length.to!(Parameters!(T.encode)[0])) ~ payload;
		}
		return this.socket.send(payload);
	}
	
	/**
	 * Returns: an array of bytes as indicated by the length or an empty array on failure
	 */
	public override ubyte[] receive() {
		return this.receiveImpl();
	}

	private ubyte[] receiveImpl() {
		if(this.nextLength == 0) {
			while(this.next.length < requiredSize) {
				if(!this.read()) return [];
			}
			static if(isNumeric!T) {
				this.nextLength = _read!T(this.next);
			} else {
				this.nextLength = T.fromBuffer(this.next);
			}
			if(this.nextLength == 0) {
				// valid connection but length was 0
				return [];
			} else {
				return this.receiveImpl();
			}
		} else {
			while(this.next.length < this.nextLength) {
				if(!this.read()) return [];
			}
			ubyte[] ret = this.next[0..this.nextLength];
			this.next = this.next[this.nextLength..$];
			this.nextLength = 0;
			return ret;
		}
	}
	
	/**
	 * Returns: true if some data has been received, false if the connection has been closed or timed out
	 */
	private bool read() {
		auto recv = this.socket.receive(this.buffer);
		if(recv >= 0) {
			this.next ~= this.buffer[0..recv].dup;
			return true;
		} else {
			return false;
		}
	}
	
}
