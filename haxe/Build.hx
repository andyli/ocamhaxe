import haxe.io.Path;

class Build {

	static var CFG = @:privateAccess Config.CFG;

	var cygwinPath : String;

	function new() {
	}

	function log( msg : String ) {
		Sys.println(msg);
	}

	function command(cmd,args:Array<String>) {
		log("> "+cmd+" "+args.join(" "));
		var r = Sys.command(cmd,args);
		if( r != 0 ) throw "Command exit with code "+r;
	}

	function deleteFile(path:String) {
		try sys.FileSystem.deleteFile(path) catch(e : Dynamic) {}
	}

	function makeDir(path:String) {
		try sys.FileSystem.createDirectory(path) catch(e:Dynamic) {}
	}

	function cygCommand(cmd,args:Array<String>) {
		command("bash",["-c",cmd+" "+args.join(" ")]);
	}

	var copiedFiles = new Map();

	function cygCopyFile( file : String ) {

		copiedFiles.set(file, true);
		try sys.io.File.copy(Path.join([cygwinPath, file]), Path.join(["mingw", file])) catch( e : Int ) log("*** MISSING " + file+" in your Cygwin install ***");

		if( !StringTools.endsWith(file.toLowerCase(),".exe") )
			return;

		// look for dll dependencies
		var o = new sys.io.Process("cygcheck.exe",[Path.join(["mingw", file])]);
		var lines = o.stdout.readAll().toString().split("\n");
		o.exitCode();
		var r = ~/^  [A-Za-z0-9_-]+\.dll$/;
		for( f in lines ) {
			var f = StringTools.trim(f);
			if( !r.match(f) || copiedFiles.exists(f) ) continue;
			if( !sys.FileSystem.exists(Path.join([cygwinPath, "bin", f])) ) continue;
			cygCopyFile(Path.join(["bin", f]));
		}
	}

	function detectCygwin() {
		var p = new sys.io.Process("where.exe",["cygpath.exe"]);
		if( p.exitCode() != 0 ) {
			log("Cygwin not found");
			Sys.exit(1);
		}
		cygwinPath = StringTools.trim(p.stdout.readAll().toString()).substr(0,-15);
	}

	function cygCopyDir( dir : String ) {
		makeDir(Path.join(["mingw", dir]));
		cygCopyRec(dir);
	}

	function cygCopyRec( dir : String ) {
		var cygDir = Path.join([cygwinPath, dir]);
		var files = try sys.FileSystem.readDirectory(cygDir) catch( e : Dynamic ) {
			log("*** MISSING "+dir+" in your Cygwin install ***");
			return;
		}
		for( f in files )
			if( sys.FileSystem.isDirectory(Path.join([cygDir, f])) ) {
				makeDir(Path.join(["mingw", dir, f]));
				cygCopyRec(Path.join([dir, f]));
			} else
				cygCopyFile(Path.join([dir, f]));
	}

	function build() {

		// build minimal mingw distrib to use if the user doesn't have cygwin installed

		detectCygwin();
		Sys.println("Preparing mingw distrib...");
		makeDir("mingw/bin");
		for( f in CFG.cygwinTools )
			cygCopyFile("bin/"+ f + ".exe");
		cygCopyDir("usr/i686-w64-mingw32");
		cygCopyDir("lib/gcc/i686-w64-mingw32");
		makeDir("mingw/tmp");

		// build opam repo with packages necessary for haxe

		Sys.println("Preparing opam...");

		var opam = "opam32.tar.xz";
		var ocaml = CFG.ocamlVersion + "+mingw32";

		if( !sys.FileSystem.exists("bin") ) {
			// install opam
			deleteFile(opam);
			command("wget",["https://github.com/fdopen/opam-repository-mingw/releases/download/0.0.0.1/"+opam]);
			command("tar",["-xf",opam,"--strip-components","1"]);
			deleteFile(opam);
			deleteFile("install.sh");
		}

		// copy necessary runtime files so they are added to PATH in Config
		for( lib in CFG.mingwLibs ) {
			var out = "bin/"+lib+".dll";
			if( !sys.FileSystem.exists(out) )
				sys.io.File.copy("mingw/usr/i686-w64-mingw32/sys-root/mingw/bin/"+lib+".dll",out);
		}

		var cwd = Sys.getCwd().split("\\").join("/");
		var opamRoot = cwd+".opam";

		// temporarily modify the env
		Sys.putEnv("PATH", cwd+"bin;" + Sys.getEnv("PATH"));
		Sys.putEnv("OPAMROOT", opamRoot);

		if( !sys.FileSystem.exists(opamRoot) )
			cygCommand("opam",["init","--yes","default","https://github.com/fdopen/opam-repository-mingw.git","--comp",ocaml,"--switch",ocaml]);

		cygCommand("opam",["switch",ocaml]);
		cygCommand("opam",["install","--yes"].concat(CFG.opamLibs));

		Sys.println("DONE");
	}

	static function main() {
		if( sys.FileSystem.exists("Build.hx") ) Sys.setCwd("..");
		new Build().build();
	}

}
