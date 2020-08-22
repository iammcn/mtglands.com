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
            var scriptPath = @"C:\Users\foneb\OneDrive\Documents\mtglands.com\";

            GetScryFallLandsJson(scriptPath + "img");

            if (Directory.Exists(perlPath) && Directory.Exists(scriptPath))
            {
                var proc = new Process();
                proc.StartInfo = new ProcessStartInfo()
                {
                    FileName = $"{perlPath}perl.exe",
                    Arguments = $"{scriptPath}mtglands-cache.pl",
                    WorkingDirectory = scriptPath
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
            }
            else
			{
                Console.Error.WriteLine($"Could not find perl: {perlPath}");
			}
        }

        static void GetScryFallLandsJson(string imageDirectory)
		{
            // https://github.com/restsharp/RestSharp/wiki
            // https://www.newtonsoft.com/json/help/html/Introduction.htm
            var webClient = new System.Net.WebClient();

            var client = new RestClient();
            var request = new RestRequest();

            string resource = "https://api.scryfall.com/cards/search?q=t%3Aland";

            while (true)
            {
                request.Resource = resource;

                IRestResponse response = client.Execute(request);

                var content = (MagicCardList)JsonConvert.DeserializeObject<MagicCardList>(response.Content);

                if (!Directory.Exists(Path.Combine(imageDirectory, "large")))
                {
                    Directory.CreateDirectory(Path.Combine(imageDirectory, "large"));
                    foreach (var card in content.data)
                    {
                        if (card.image_uris != null)
                        {
                            webClient.DownloadFile(card.image_uris.normal, System.IO.Path.Combine(imageDirectory, "large", card.id + ".jpg"));
                        }
                        else
                        {
                            webClient.DownloadFile(card.card_faces[1].image_uris.normal, System.IO.Path.Combine(imageDirectory, "large", card.id + ".jpg"));
                        }
                            
                        System.Threading.Thread.Sleep(100);
                    }
                }
                if (!Directory.Exists(Path.Combine(imageDirectory, "small")))
                {
                    Directory.CreateDirectory(Path.Combine(imageDirectory, "small"));
                    foreach (var card in content.data)
                    {
                        if (card.image_uris != null)
                        {
                            webClient.DownloadFile(card.image_uris.small, System.IO.Path.Combine(imageDirectory, "small", card.id + ".jpg"));
                        }
                        else
                        {
                            webClient.DownloadFile(card.card_faces[1].image_uris.small, System.IO.Path.Combine(imageDirectory, "small", card.id + ".jpg"));
                        }

                        System.Threading.Thread.Sleep(50);
                    }
                }

                if (string.IsNullOrEmpty(content.next_page))
                {
                    break;
                }

                resource = content.next_page;

                System.Threading.Thread.Sleep(100);
            }
        }
    }
}
