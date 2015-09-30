module dpaste.backend.execute;

import vibe.data.json: Json;
import vibe.core.log: logTrace, logError;

import core.time: Duration;

import dpaste.backend.common;

struct Runtime 
{
	// Full path to the created executable
	string binaryPath;

	// StandardInput stream provided by user
	string standardInput;

	// Command Line arguments provided by user
}

Json execute(Json request, User user, Duration timeout)
{
	import std.file: chdir;
	import std.process: pipeProcess, ProcessPipes, ProcessException;
	import core.sys.posix.unistd: seteuid, setegid;


	string binPath = user.homePath ~ "/app";

	// At this point drop privilages
	logTrace("Lowerring privilages to: UID(%d), GID(%d)", user.id, user.groupId);
	setegid(user.groupId);
	seteuid(user.id);

	ProcessPipes pipe;
	string[] runtimeArguments = [binPath];
	runtimeArguments ~= parseArgs(request["cmdArguments"].get!string);

	logTrace("Chaning working directory to %s", user.homePath);
	chdir(user.homePath);
	
	try 
	{
		logTrace("Invoking executable with following arguments: %s", runtimeArguments);
		pipe = pipeProcess(runtimeArguments);
	}
	catch (ProcessException e)
	{
		logError(
			"Caught exception while trying to execute program with following arguments: %s. "
			"Exception details: %s (%s: %d)",
			runtimeArguments, e.msg, e.file, e.line
		);
		
		return jsonError("Internal error: Couldn't execute compiler");
	}
	
	auto ret = processInputOutput(pipe, request["standardInput"].get!string, timeout);
	logTrace("Compilation result: %s", ret);
	
	Json response = Json.emptyObject;
	response["status"] = ret.status;
	response["stdout"] = ret.stdout;
	response["stderr"] = ret.stderr;
	
	return response;
}

private string[] parseArgs(string args) pure nothrow @safe
{
	string[] parts;
	bool inQuote;
	char prev, curr;
	string buff;
	
	for (size_t i; i < args.length; i++) {
		curr = args[i];
		
		if ((curr == '"' || curr == '`') && prev != '\\') {
			inQuote = !inQuote;
		} else if (curr == ' ' && !inQuote) {
			parts ~= buff;
			buff = "";
		} else {
			buff ~= curr;
		}
		
		prev = curr;
	}
	
	parts ~= buff;
	
	return parts;
}