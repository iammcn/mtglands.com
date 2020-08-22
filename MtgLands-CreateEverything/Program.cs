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
            var perlPath = @"C:\Perl\Strawberry\perl\bin\";
            var rootPath = @"C:\Users\foneb\OneDrive\Documents\mtglands.com\";

            if (Directory.Exists(perlPath) && Directory.Exists(rootPath))
            {
                var proc = new Process();
                proc.StartInfo = new ProcessStartInfo()
                {
                    FileName = $"{perlPath}perl.exe",
                    Arguments = $"{rootPath}mtglands-cache.pl",
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

                    var guid = split[0];
                    var largeFileName = split[1];
                    var smallFileName = split[2];
                    {
                        var uri = new Uri($"https://api.scryfall.com/cards/{guid}?format=image&version=large");
                        var filePath = Path.Combine(rootPath, largeFileName);
                        if (!File.Exists(filePath))
                        {
                            webClient.DownloadFile(uri, filePath);
                            System.Threading.Thread.Sleep(100);
                        }
                    }
                    {
                        var uri = new Uri($"https://api.scryfall.com/cards/{guid}?format=image&version=normal");
                        var filePath = Path.Combine(rootPath, smallFileName);
                        if (!File.Exists(filePath))
                        {
                            webClient.DownloadFile(uri, filePath);
                            System.Threading.Thread.Sleep(100);
                        }
                    }
                }
            }
        }
    }
}
