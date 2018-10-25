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

			public IVDServer Initialize()
			{
				var instance = new VDServer();
				instance.ConfigureSemanticProject(null, subFolder, "", "", "", 0);
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
				int remainingAttempts = 100;
				do
				{
					Thread.Sleep(100);
					instance.GetTipResult(out var startLine, out var startIndex,
						out var endLine, out var endIndex, out answer);
				} while (answer == "__pending__" && remainingAttempts-- > 0);

				Assert.That(answer, Is.EqualTo("void test.main()"));
			}
		}
	}
}