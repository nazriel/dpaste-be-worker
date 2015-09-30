enum Mode : string 
{
	compilation = "compilation",
	runtime = "runtime"
}

void main(string[] args) 
{
	import core.time: seconds, Duration;
	import std.conv: to;
	import std.file: readLink;
	import std.stdio: File, readln, stdout;
	import std.path: dirName;

	import vibe.data.json;
	import vibe.core.args;
	import vibe.core.log;
	
	import dpaste.backend.common: readConfigFile, User;
	import dpaste.backend.compile: compile;
	import dpaste.backend.execute: execute;

	string appDir = readLink("/proc/self/exe").dirName();

	setLogLevel(LogLevel.none);
	auto logger = cast(shared) new FileLogger(
		File(appDir ~ "/worker.log", "w+"), 
		File(appDir ~ "/worker.trace.log", "w+")
	);
	registerLogger(logger);

	logInfo("appDir %s", appDir);

	User user;

	user.name = readRequiredOption!string("userName", "Name  of the user under which application will be executed");
	user.homePath = readRequiredOption!string("homePath", "Full path to the home directory of supplied user");
	user.id = readRequiredOption!uint("userId", "System UID of the user under which application will be executed");
	user.groupId = readRequiredOption!uint("groupId", "System GUID of the group under which application will be executed");
	user.permission = readRequiredOption!string(
		"permission", 
		"DPaste permission level of given user. Can be: guest, registered, dlang"
	).to!(User.Permissions);

	Json configuration;
	readConfigFile(appDir ~ "/config.json", configuration);

	Mode mode = readRequiredOption!string(
		"mode", 
		"Mode in which worker will be executed. Can be: compilation, runtime"
	).to!Mode;

	uint timeout = readRequiredOption!uint(
		"timeout", 
		"Timeout after which compilation/runtime should be terminated (in seconds)"
	);

	Json request = readln().parseJsonString();

	Json response = Json.emptyObject;

	with(Mode) switch (mode)
	{
	default:
	case compilation:
		logTrace("Starting compilation process");
		response = compile(request, user, configuration, timeout.seconds);
		break;
	case runtime:
		logTrace("Starting runtime process");
		response = execute(request, user, timeout.seconds);
		break;
	}

	logTrace("Sending response to the daemon process via stdout: %s", response.toString());
	stdout.writeln(response.toString());
	stdout.flush();
	stdout.close();
}