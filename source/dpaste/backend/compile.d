module dpaste.backend.compile;

import vibe.data.json;
import vibe.core.log;

import core.time: Duration;

import dpaste.backend.common;

enum Vendor : string 
{
	dmd = "dmd",
	ldc = "ldc",
	gdc = "gdc"
}

struct Compiler
{
	Vendor vendor;
	uint versionInt;
	string versionString;

	// Full path to the binary file of compiler
	string binPath;

	// Array of paths in which compiler should look for includes 
	string[] includePath;

	// Array of *paths* in which linker should look for libraries
	string[] libPath;

	// Array of *files* or *flags* which linker should use - optional
	string[] libFiles;

	/**
	 * 
	 * Translates general JSON arguments for compiler into compiler specific switches +
	 * appends paths to includes, libs etc;
	 * 
	 * JSON should have following format:
	 * {["version": "a", "version": "b", "debug=3"]} etc
	 * @return: string[] 
	 */
	public string[] generateArguments(Json requestDetails)
	{
		with (Vendor)
		final switch (vendor)
		{
			case dmd:
				return generateArgumentsDMD(requestDetails);
			case ldc:
				return generateArgumentsLDC(requestDetails);
			case gdc:
				return generateArgumentsGDC(requestDetails);
		}
	}

private:
	string[] generateArgumentsDMD(Json requestDetails)
	{
		import std.array: appender;

		auto result = appender!(string[])();

		// Include paths
		foreach (path; includePath)
		{
			result.put("-I"~path);
		}

		// Library paths
		foreach (path; libPath)
		{
			result.put("-L-L" ~ path);
		}
		result.put("-L--export-dynamic");

		foreach (file; libFiles)
		{
			result.put("-L"~file);
		}

		if (requestDetails["mode"].get!int == 64)
		{
			result.put("-m64");
		}
		else
		{
			result.put("-m32");
		}

		//foreach (key, value; requestDetails["compiler"]["switches"])
		{

		}

		return result.data;
	}

	string[] generateArgumentsLDC(Json requestDetails)
	{
		return [];
	}

	string[] generateArgumentsGDC(Json requestDetails)
	{
		return [];
	}
}

Compiler findRequestedCompiler(Json request, Json configuration)
{
	import std.string: toUpper;

	Compiler foundCompiler;

	string vendor = request["compiler"]["vendor"].get!string;
	string versionString = request["compiler"]["versionString"].get!string;

	logTrace("Searching for compiler: %s %s", vendor.toUpper(), versionString);
	logTrace("Available compiler's configuration in JSON format: %s", configuration["compilers"].toString());

	foreach (compiler; configuration["compilers"])
	{
		if (compiler["vendor"].get!string == vendor && compiler["versionString"].get!string == versionString)
		{
			foundCompiler.vendor = deserializeJson!Vendor(compiler["vendor"]);
			foundCompiler.versionInt = compiler["version"].get!uint();
			foundCompiler.versionString = versionString;

			foundCompiler.binPath = compiler["binPath"].get!string;
			foundCompiler.includePath = deserializeJson!(string[])(compiler["includesPath"]);

			if (request["mode"].get!int == 64)
			{
				foundCompiler.libPath = deserializeJson!(string[])(compiler["libs64Path"]);
				if ("libs64Files" in compiler)
				{
					foundCompiler.libFiles = deserializeJson!(string[])(compiler["libs64Files"]);
				}
			}
			else
			{
				foundCompiler.libPath = deserializeJson!(string[])(compiler["libs32Path"]);
				if ("libs32Files" in compiler)
				{
					foundCompiler.libFiles = deserializeJson!(string[])(compiler["libs32Files"]);
				}
			}

			with (foundCompiler)
			logTrace(
				"Found requested compiler, details: vendor(%s), version(%s), binPath(%s), includePath(%s), libPath(%s)",
				vendor.toUpper(), versionString, binPath, includePath, libPath
			);
			break;
		}
	}

	return foundCompiler;
}

Json compile(Json request, User user, Json configuration, Duration timeout)
{
	import std.file: write, FileException, chdir;
	import std.process: pipeProcess, ProcessPipes, ProcessException;
	import std.string: format, toUpper;

	import core.sys.posix.unistd: seteuid, setegid;

	Compiler compiler = findRequestedCompiler(request, configuration);

	if (compiler == Compiler.init)
	{
		string err = "Couldn't find request compiler: %s %s".format(
			request["compiler"]["vendor"].get!string.toUpper(), 
			request["compiler"]["versionString"].get!string
		);

		logError(err);
		return jsonError(err);
	}

	string sourceFilePath = user.homePath ~ "/app.d";

	try
	{
		logTrace("Writing program source to '%s' file", sourceFilePath);
		write(sourceFilePath, request["source"].get!string);
	}
	catch (FileException e)
	{
		logError(
			"Caught exception while trying to write '%s' file. Exception details: %s (%s: %d)", 
			sourceFilePath, e.msg, e.file, e.line
		);

		return jsonError("Internal error: Couldn't write source file");
	}

	// At this point drop privilages
	logTrace("Lowerring privilages to: UID(%d), GID(%d)", user.id, user.groupId);
	setegid(user.groupId);
	seteuid(user.id);

	ProcessPipes pipe;
	string[] compilerArguments = [
		compiler.binPath,
		sourceFilePath
	];
	compilerArguments ~= compiler.generateArguments(request);

	logTrace("Chaning working directory to %s", user.homePath);
	chdir(user.homePath);

	try 
	{
		logTrace("Invoking compiler with following arguments: %s", compilerArguments);
		pipe = pipeProcess(compilerArguments);
	}
	catch (ProcessException e)
	{
		logError(
			"Caught exception while trying to compile program with following arguments: %s. "
			"Exception details: %s (%s: %d)",
			compilerArguments, e.msg, e.file, e.line
		);

		return jsonError("Internal error: Couldn't execute compiler");
	}

	auto ret = processInputOutput(pipe, null, timeout);
	logTrace("Compilation result: %s", ret);

	Json response = Json.emptyObject;
	response["status"] = ret.status;
	response["stdout"] = ret.stdout;
	response["stderr"] = ret.stderr;

	return response;
}

version(none):

import dpaste.backend.common;
import std.array: Appender, appender;


enum Compilers
{
	DMD,
	LDC,
	GDC
}

struct Compiler
{
	string binPath;
	string includePath;
	string libPath;

	string[] args;

	void translateSwitches()
	{
		this.args = [];
	}

}

struct CompilationSettings
{
	Compilers compiler;
	string compilerVersion; // DMD 2.068.1, LDC 0.12 etc

	string sourceCode;
}

struct CompilationResult
{
	int result = 0;
}

auto compile(CompilationSettings req, WorkerSettings settings)
{

}
