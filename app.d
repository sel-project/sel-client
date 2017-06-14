module app;

import std.stdio : writeln;

import sel.client;

void main(string[] args) {
	
	auto pocket = new PocketClient!113();
	
	writeln(pocket.rawPing("play.lbsg.net"));
	
	auto java = new JavaClient!335("H0LY FUCKeN $HIT");
	
}
