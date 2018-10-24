using System.Collections.Generic;
using System.Linq;
using D_Parser.Dom;
using D_Parser.Misc;

namespace DParserCOMServer
{
	class VDserverParseCacheView : ParseCacheView
	{
		#region Properties
		readonly List<RootPackage> packs;
		#endregion
		public string[] PackageRootDirs { get; private set; }

		#region Constructors
		public VDserverParseCacheView(string[] packageRoots)
		{
			this.PackageRootDirs = packageRoots;
			this.packs = new List<RootPackage>();
			Add(packageRoots);
		}

		public VDserverParseCacheView(IEnumerable<RootPackage> packages)
		{
			this.packs = new List<RootPackage>(packages);
		}
		#endregion

		public override IEnumerable<RootPackage> EnumRootPackagesSurroundingModule(DModule module)
		{
			// if packs not added during construction because not yet parsed by GlobalParseCache, try adding now
			if (packs.Count() != PackageRootDirs.Count())
				Add(PackageRootDirs);
			return packs;
		}

		public void Add(RootPackage pack)
		{
			if (pack != null && !packs.Contains(pack))
				packs.Add(pack);
		}

		public void Add(IEnumerable<string> roots)
		{
			RootPackage rp;
			foreach (var r in roots)
				if ((rp = GlobalParseCache.GetRootPackage(r)) != null && !packs.Contains(rp))
					packs.Add(rp);
		}
	}
}