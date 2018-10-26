using System;
using System.IO;
using System.Threading;
using D_Parser.Misc;
using NUnit.Framework;

namespace DParserCOMServer.Tests
{
	[TestFixture]
	public class Tests
	{
		class VDServerDisposable : IDisposable
		{
			public readonly string subFolder;
			public readonly string moduleFile;
			private readonly string moduleCode;
			private readonly SemaphoreSlim _parseFinishedSemaphore = new SemaphoreSlim(0);

			public VDServerDisposable(string moduleCode)
			{
				this.moduleCode = moduleCode;
				var tempDirectory = Path.GetTempPath();
				subFolder = Path.Combine(tempDirectory, "vdserver_test");
				Directory.CreateDirectory(subFolder);
				moduleFile = Path.Combine(subFolder, "test.d");

				File.WriteAllText(moduleFile, moduleCode);

				GlobalParseCache.ParseTaskFinished += ParseTaskFinished;
			}

			private void ParseTaskFinished(ParsingFinishedEventArgs ea)
			{
				if (ea.Directory.StartsWith(subFolder))
				{
					_parseFinishedSemaphore.Release(1);
				}
			}

			public IVDServer Initialize(uint flags = 0)
			{
				var instance = new VDServer();
				instance.ConfigureSemanticProject(null, subFolder, "", "", "", flags);
				Console.WriteLine("Waiting for " + subFolder + " to be parsed...");
				Assert.That(_parseFinishedSemaphore.Wait(10000));
				Console.WriteLine("Finished parsing " + subFolder);
				instance.UpdateModule(moduleFile, moduleCode, 0);
				return instance;
			}

			public void Dispose()
			{
				Console.WriteLine("Deleting folder " + subFolder);
				Directory.Delete(subFolder, true);
			}
		}

		static uint CompileFlags(VDServerEditorFlags flags, byte debugLevel = 0, byte versionNumber = 0)
		{
			var compiledFlags = (uint)flags;
			compiledFlags |= (uint) versionNumber << 8;
			compiledFlags |= (uint) debugLevel << 16;
			return compiledFlags;
		}

		[Test]
		public void GetTip()
		{
			var code = @"module test;
void main() {}";

			using (var vd = new VDServerDisposable(code))
			{
				var instance = vd.Initialize();
				instance.GetTip(vd.moduleFile, 2, 7, 2, 7, 0);

				string answer;
				int remainingAttempts = 200;
				do
				{
					Thread.Sleep(200 - remainingAttempts);
					instance.GetTipResult(out var startLine, out var startIndex,
						out var endLine, out var endIndex, out answer);
				} while (answer == "__pending__" && remainingAttempts-- > 0);

				Assert.That(answer, Is.EqualTo("void test.main()"));
			}
		}

		[Test]
		public void GetSemanticExpensions()
		{
			var code = @"module test;
void foo() {
	A!`asdf` a;
a.
}

class A(string mixinCode) {
	mixin(`int ` ~ mixinCode ~ `;`);
	int bar();
	string c = mixinCode;
}";

			using (var vd = new VDServerDisposable(code))
			{
				var instance = vd.Initialize(CompileFlags(VDServerEditorFlags.EnableMixinAnalysis));
				instance.GetSemanticExpansions(vd.moduleFile, String.Empty, 4, 2, null);

				string answer;
				int remainingAttempts = 200;
				do
				{
					Thread.Sleep(200 - remainingAttempts);
					instance.GetSemanticExpansionsResult(out answer);
				} while (answer == "__pending__" && remainingAttempts-- > 0);

				Assert.NotNull(answer);
				var receivedExpansions = answer.Split(new []{'\n'}, StringSplitOptions.RemoveEmptyEntries);
				var expectedExpansions = new[]
				{
					"asdf:VAR:int test.A.asdf",
					"bar:MTHD:int test.A.bar()",
					"c:VAR:string test.A.c",
					"init:SPRP:static A!mixinCode init\aA type's or variable's static initializer expression",
					"sizeof:SPRP:static uint sizeof\aSize of a type or variable in bytes",
					"alignof:SPRP:uint alignof\aVariable alignment",
					"mangleof:SPRP:static string mangleof\a"
					+ "String representing the ‘mangled’ representation of the type",
					"stringof:SPRP:static string stringof\aString representing the source representation of the type",
					"classinfo:SPRP:object.TypeInfo_Class classinfo\aInformation about the dynamic type of the class"
				};
				CollectionAssert.AreEquivalent(expectedExpansions, receivedExpansions);
			}
		}
	}
}