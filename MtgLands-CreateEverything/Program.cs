using System;
using System.Diagnostics;
using System.IO;

namespace MtgLands_CreateEverything
{
    class Program
    {
        static void Main(string[] args)
        {
            var rootPath = args[0];
            var wwwPath = args[1];

            if (Directory.Exists(rootPath))
            {
                CreateAllRequiredDirectories(wwwPath);

                CopyFilesFromRoot(rootPath, wwwPath);

                var proc = new Process();
                proc.StartInfo = new ProcessStartInfo()
                {
                    FileName = "perl.exe",
                    Arguments = string.Join(' ', Path.Combine(rootPath, "mtglands-cache.pl"), wwwPath),
                    WorkingDirectory = rootPath
                };

                if (proc.Start())
                {
                    while (true)
                    {
                        if (proc.WaitForExit(100))
                        {
                            if (proc.ExitCode != 0)
                            {
                                return;
                            }
                            else
                            {
                                break;
                            }
                        }
                    }
                }

                GetImagesFromScryfall(wwwPath);
            }
            else
			{
                Console.Error.WriteLine($"Could not find root path: {rootPath}");
			}
        }

		private static void CreateAllRequiredDirectories(string wwwPath)
        {
            Directory.CreateDirectory(Path.Combine(wwwPath, "script"));
            Directory.CreateDirectory(Path.Combine(wwwPath, "style"));
            var imageDirectory = Path.Combine(wwwPath, "img");
            Directory.CreateDirectory(Path.Combine(imageDirectory, "large"));
            Directory.CreateDirectory(Path.Combine(imageDirectory, "small"));
        }

        private static void CopyFilesFromRoot(string rootPath, string wwwPath)
        {
            File.Copy(Path.Combine(rootPath, "img", "mana.svg"), Path.Combine(wwwPath, "img", "mana.svg"), true);

            File.Copy(Path.Combine(rootPath, "script", "js.cookie.js"), Path.Combine(wwwPath, "script", "js.cookie.js"), true);
            File.Copy(Path.Combine(rootPath, "script", "main.js"), Path.Combine(wwwPath, "script", "main.js"), true);

            File.Copy(Path.Combine(rootPath, "style", "main.css"), Path.Combine(wwwPath, "style", "main.css"), true);
            File.Copy(Path.Combine(rootPath, "style", "mana.css"), Path.Combine(wwwPath, "style", "mana.css"), true);
        }

        static void GetImagesFromScryfall(string wwwPath)
        {
            Console.WriteLine("Getting Images From Scryfall...");
            //https://api.scryfall.com/cards/{guid}?format=image&version=normal
            var webClient = new System.Net.WebClient();

            var imageDirectory = Path.Combine(wwwPath, "img");

            using (var file = new StreamReader(Path.Combine(imageDirectory, "TEMP_IMAGE_DOWNLOAD_LIST.txt")))
            {
                while (true)
                {
                    var line = file.ReadLine();

                    if (line == null)
                        break;

                    var split = line.Split(' ');

                    (string guid, string largeFileName, string smallFileName, string isTransformCard) = (split[0], split[1], split[2], split[3]);

                    var getCardBack = "";
                    if (isTransformCard == "true")
					{
                        getCardBack = "&face=back";
                    }

                    {
                        //https://c1.scryfall.com/file/scryfall-cards/png/front/c/4/c4ac7570-e74e-4081-ac53-cf41e695b7eb.png?1562563598
                        //https://api.scryfall.com/cards/c4ac7570-e74e-4081-ac53-cf41e695b7eb?format=image&version=large&face=back
                        var filePath = Path.Combine(wwwPath, largeFileName);
                        if (!File.Exists(filePath))
                        {
                            var uri = new Uri($"https://api.scryfall.com/cards/{guid}?format=image&version=large{getCardBack}");
                            webClient.DownloadFile(uri, filePath);
                            System.Threading.Thread.Sleep(100);
                        }
                    }
                    {
                        var filePath = Path.Combine(wwwPath, smallFileName);
                        if (!File.Exists(filePath))
                        {
                            var uri = new Uri($"https://api.scryfall.com/cards/{guid}?format=image&version=normal{getCardBack}");
                            webClient.DownloadFile(uri, filePath);
                            System.Threading.Thread.Sleep(100);
                        }
                    }
                }
            }
        }
    }
}
