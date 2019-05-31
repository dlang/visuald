using System;
using System.IO;
using System.Threading;
using D_Parser.Misc;
using NUnit.Framework;
using DParserCOMServer.CodeSemantics;

namespace DParserCOMServer.Tests
{
	[TestFixture]
	public class Tests
	{
		static Tests()
		{
			CompletionOptions.Instance.CompletionTimeout = -1;
		}

		class VDServerDisposable : IDisposable
		{
			private static volatile int _folderSuffix = 0;
			readonly string _subFolder;
			public readonly string FirstModuleFile;
			public readonly string[] ModuleFileNames;
			private readonly string[] _moduleCodes;
			private readonly ManualResetEvent _parseFinishedSemaphore = new ManualResetEvent(false);

			public VDServerDisposable(params string[] moduleCodes)
			{
				_moduleCodes = moduleCodes;
				ModuleFileNames = new string[moduleCodes.Length];
				var tempDirectory = Path.GetTempPath();
				_subFolder = Path.Combine(tempDirectory, "vdserver_test" + Interlocked.Increment(ref _folderSuffix));
				_subFolder = EditorDataProvider.normalizeDir(_subFolder);
				Directory.CreateDirectory(_subFolder);

				for(var fileIterator = 0; fileIterator < moduleCodes.Length; fileIterator++)
				{
					var file = Path.Combine(_subFolder, "test" + fileIterator + ".d");
					ModuleFileNames[fileIterator] = file;
					File.WriteAllText(file, moduleCodes[fileIterator]);
				}
				FirstModuleFile = ModuleFileNames.Length > 0 ? ModuleFileNames[0] : String.Empty;

				GlobalParseCache.ParseTaskFinished += ParseTaskFinished;
			}

			private void ParseTaskFinished(ParsingFinishedEventArgs ea)
			{
				Console.WriteLine("Parse task finished: " + ea.Directory);
				if (!ea.Directory.StartsWith(_subFolder))
				{
					Assert.Warn("Received ParseTaskFinished-Event for wrong directory (" + ea.Directory + ")");
					return;
				}

				var moduleFiles = GlobalParseCache.EnumModulesRecursively(_subFolder).ConvertAll(module => module.FileName);
				CollectionAssert.AreEquivalent(moduleFiles, ModuleFileNames);
				_parseFinishedSemaphore.Set();
			}

			public IVDServer Initialize(uint flags = 0)
			{
				IVDServer instance = new VDServer();
				instance.ConfigureSemanticProject(null, _subFolder, "", "", "", flags);
				Console.WriteLine("Waiting for " + _subFolder + " to be parsed...");
				if (!_parseFinishedSemaphore.WaitOne(5000))
				{
					Console.WriteLine("Didn't finish parsing " + _subFolder + " soon enough. Try to continue testing...");
				}
				else
				{
					Console.WriteLine("Finished parsing " + _subFolder);
				}

				for (int moduleIndex = 0; moduleIndex < ModuleFileNames.Length; moduleIndex++)
				{
					var file = ModuleFileNames[moduleIndex];
					instance.UpdateModule(file, _moduleCodes[moduleIndex], 0);
				}

				return instance;
			}

			public void Dispose()
			{
				GlobalParseCache.ParseTaskFinished -= ParseTaskFinished;
				Console.WriteLine("Deleting folder " + _subFolder);
				Directory.Delete(_subFolder, true);
				if(_parseFinishedSemaphore.WaitOne(0))
					Assert.That(GlobalParseCache.RemoveRoot(_subFolder));
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
void maintip() {}";

			using (var vd = new VDServerDisposable(code))
			{
				var instance = vd.Initialize();
				instance.GetTip(vd.FirstModuleFile, 2, 7, 2, 7, 0);

				string answer;
				int remainingAttempts = 200;
				do
				{
					Thread.Sleep(200 - remainingAttempts);
					instance.GetTipResult(out var startLine, out var startIndex,
						out var endLine, out var endIndex, out answer);
				} while (answer == "__pending__" && remainingAttempts-- > 0);

				Assert.That(answer, Is.EqualTo("void test.maintip()"));
			}
		}

		[Test]
		public void GetSemanticExpansions()
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
				instance.GetSemanticExpansions(vd.FirstModuleFile, String.Empty, 4, 2, null);

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

		[Test]
		public void GetDefinition()
		{
			var code_A = @"module test0;
void foo();";
			var code_B = @"module test1; import test0;
void main() {
foo();
}";
			using (var vd = new VDServerDisposable(code_A, code_B))
			{
				var instance = vd.Initialize();
				instance.GetDefinition(vd.ModuleFileNames[1], 3, 0, 3, 1);

				string targetFilename;
				int startLine, startIndex, endLine, endIndex;
				int remainingAttempts = 200;
				do
				{
					Thread.Sleep(200 - remainingAttempts);
					instance.GetDefinitionResult(out startLine, out startIndex,
						out endLine, out endIndex, out targetFilename);
				} while (targetFilename == "__pending__" && remainingAttempts-- > 0);

				Assert.That(targetFilename, Is.EqualTo("EXTERN:" + vd.FirstModuleFile));
				Assert.That(startLine, Is.EqualTo(2));
			}
		}

		[Test]
		public void GetParseErrors()
		{
			var code = @"module test0;
void foo() {
a.
}";

			using (var vd = new VDServerDisposable(code))
			{
				var instance = vd.Initialize();
				instance.GetParseErrors(vd.FirstModuleFile, out var errors);
				Assert.That(errors, Is.EqualTo(@"4,0,4,1:<Identifier> expected, } found!
4,0,4,1:; expected, } found!
"));
			}
		}

		[Test]
		public void GetReferences()
		{
			var code = @"module A;
int foo();
enum enumFoo = foo();
void main(){
foo();
}";
			using (var vd = new VDServerDisposable(code))
			{
				var instance = vd.Initialize();
				instance.GetReferences(vd.FirstModuleFile, null, 5, 0, null, false);

				string answer;
				int remainingAttempts = 200;
				do
				{
					Thread.Sleep(200 - remainingAttempts);
					instance.GetReferencesResult(out answer);
				} while (answer == "__pending__" && remainingAttempts-- > 0);

				Assert.NotNull(answer);
				var references = answer.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
				var expectedReferences = new[]
				{
					"2,4,2,7:" + vd.FirstModuleFile + "|int foo();",
					"3,15,3,18:" + vd.FirstModuleFile + "|enum enumFoo = foo();",
					"5,0,5,3:" + vd.FirstModuleFile + "|foo();"
				};
				CollectionAssert.AreEquivalent(expectedReferences, references);
			}
		}

		[Test]
		public void GetIdentifierTypes()
		{
			using (var vd = new VDServerDisposable(@"module A;"))
			{
				var instance = vd.Initialize();
				instance.UpdateModule(vd.FirstModuleFile, @"module A;
void foo();
void bar(){
	struct NestedStruct{}
}
class MyClass{}
struct SomeStruct{}
MyClass a;", 2);

				instance.GetIdentifierTypes(vd.FirstModuleFile, 0, -1, 1);
				string answer;
				int remainingAttempts = 200;
				do
				{
					Thread.Sleep(200 - remainingAttempts);
					instance.GetIdentifierTypesResult(out answer);
				} while (answer == "__pending__" && remainingAttempts-- > 0);

				Assert.NotNull(answer);
				var identifierTypes = answer.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
				var expectedReferences = new[]
				{
					"foo:19",
					"bar:19",
					"NestedStruct:6",
					"MyClass:5",
					"SomeStruct:6",
					"a:16"
				};
				CollectionAssert.AreEquivalent(expectedReferences, identifierTypes);
			}
		}
	}
}