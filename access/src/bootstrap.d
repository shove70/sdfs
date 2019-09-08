import hunt;

void main()
{
    auto app = Application.getInstance();
    app.run();
}

shared static this()
{
    import hunt.application.staticfile;
    StaticfileController.onStaticFilePathSegmentation = &onStaticFilePathSegmentation;
    StaticfileController.staticFileMimetype = "text/plain";
}

string onStaticFilePathSegmentation(const string path, const string filename) nothrow
{
	import std.path : buildPath, stripExtension;
	import std.file : exists;

    string name = stripExtension(filename);

    if (name.length < 9)
    {
        return string.init;
    }

    name = buildPath(path, name[0..3], name[3..6], name[6..9], name);

	string name2 = name ~ "$$";
	if (name2.exists)
	{
		return name2;
	}

	name2 = name ~ "$_";
	if (name2.exists)
	{
		return name2;
	}

	name2 = name ~ "_$";
	if (name2.exists)
	{
		return name2;
	}

	name2 = name ~ "__";
	if (name2.exists)
	{
		return name2;
	}

	return string.init;
}
