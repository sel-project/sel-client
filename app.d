module app;

import std.stdio : writeln;

import sel.client;

void main(string[] args) {
	
	auto pocket = new BedrockClient!113();
	writeln(pocket.rawPing("play.lbsg.net"));
	
	auto java = new JavaClient!335();
	writeln(java.ping("mc.wildadventure.it"));

	auto bedrock = new BedrockClient!160();
	writeln(bedrock.name);
	
}
