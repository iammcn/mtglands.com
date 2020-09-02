using Cooper.Magic.ScryFall;
using System;
using System.Diagnostics;
using System.IO;
using RestSharp;
using Newtonsoft.Json;

namespace MtgLands_CreateEverything
{
    class Program
    {
        static void Main(string[] args)
        {
            var rootPath = args[0];

            if (Directory.Exists(rootPath))
            {
                var proc = new Process();
                proc.StartInfo = new ProcessStartInfo()
                {
                    FileName = "perl.exe",
                    Arguments = Path.Combine(rootPath, "mtglands-cache.pl"),
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

                GetImagesFromScryFall(rootPath);
            }
            else
			{
                Console.Error.WriteLine($"Could not find perl: {perlPath}");
			}
        }

        static void GetImagesFromScryFall(string rootPath)
        {
            Console.WriteLine("Getting Images From ScryFall...");
            //https://api.scryfall.com/cards/{guid}?format=image&version=normal
            var webClient = new System.Net.WebClient();

            var imageDirectory = Path.Combine(rootPath, "img");
            Directory.CreateDirectory(Path.Combine(imageDirectory, "large"));
            Directory.CreateDirectory(Path.Combine(imageDirectory, "small"));

            using (var file = new StreamReader(Path.Combine(rootPath, "TEMP_IMAGE_DOWNLOAD_LIST.txt")))
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
                        var filePath = Path.Combine(rootPath, largeFileName);
                        if (!File.Exists(filePath))
                        {
                            var uri = new Uri($"https://api.scryfall.com/cards/{guid}?format=image&version=large{getCardBack}");
                            webClient.DownloadFile(uri, filePath);
                            System.Threading.Thread.Sleep(100);
                        }
                    }
                    {
                        var filePath = Path.Combine(rootPath, smallFileName);
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
