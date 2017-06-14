module app;

import std.stdio : writeln;

import sel.client;

void main(string[] args) {

	auto minecraft = new MinecraftClient!113();

	writeln(minecraft.rawPing("play.lbsg.net"));

	auto java = new JavaClient!335("H0LY FUCKeN $HIT");
	if(connection is null) {
		writeln("error");
		writeln(java.lastError);
	}

}
