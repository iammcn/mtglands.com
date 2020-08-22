using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;

namespace Cooper.Magic.ScryFall
{
	public class MagicCardList
	{
		[JsonProperty("object")]
		public string object_ { get; set; }
		public int total_cards { get; set; }
		public bool has_more { get; set; }
		public string next_page { get; set; }
		public MagicCard[] data { get; set; }
	}

	/// <summary>
	/// https://scryfall.com/docs/api/cards
	/// </summary>
	public class MagicCard
	{
		[JsonProperty("object")]
		public string object_ { get; set; }
		public Guid id { get; set; }
		public Guid oracle_id { get; set; }
		public int[] multiverse_ids { get; set; }
		public int arena_id { get; set; }
		public int mtgo_id { get; set; }
		public int mtgo_foil_id { get; set; }
		public string name { get; set; }
		public string lang { get; set; }
		public Uri uri { get; set; }
		public Uri scryfall_uri { get; set; }
		public string layout { get; set; }
		public bool highres_image { get; set; }
		public MagicCardImageUris image_uris { get; set; }
		public string mana_cost { get; set; }
		public double cmc { get; set; }
		public string type_line { get; set; }
		public string oracle_text { get; set; }
		public string[] colors { get; set; }
		public string[] color_identity { get; set; }
		public MagicCardLegalities legalities { get; set; }
		public bool reserved { get; set; }
		public bool foil { get; set; }
		public bool nonfoil { get; set; }
		public bool oversized { get; set; }
		public bool reprint { get; set; }
		[JsonProperty("set")]
		public string set_ { get; set; }
		[JsonProperty("set_name")]
		public string set_name_ { get; set; }
		[JsonProperty("set_uri")]
		public Uri set_uri_ { get; set; }
		[JsonProperty("set_search_uri")]
		public Uri set_search_uri_ { get; set; }
		public Uri scryfall_set_uri { get; set; }
		public Uri rulings_uri { get; set; }
		public Uri prints_search_uri { get; set; }
		public string collector_number { get; set; }
		public bool digital { get; set; }
		public string rarity { get; set; }
		public string watermark { get; set; }
		public string flavor_text { get; set; }
		public Guid illustration_id { get; set; }
		public string artist { get; set; }
		public string frame { get; set; }
		public bool full_art { get; set; }
		public string border_color { get; set; }
		public bool timeshifted { get; set; }
		public bool colorshifted { get; set; }
		public bool futureshifted { get; set; }
		public string edhrec_rank { get; set; }
		public string usd { get; set; }
		public string tix { get; set; }
		public string eur { get; set; }
		public MagicCardRelatedUris related_uris { get; set; }
		public MagicCardPurchaseUris purchase_uris { get; set; }
		public string power { get; set; }
		public string toughness { get; set; }
		public MagicCardFaces[] card_faces { get; set; }
	}
	public class MagicCardImageUris
	{
		public Uri small { get; set; }
		public Uri normal { get; set; }
		public Uri large { get; set; }
		public Uri png { get; set; }
		public Uri art_crop { get; set; }
		public Uri border_crop { get; set; }
	}
	public class MagicCardLegalities
	{
		public string standard { get; set; }
		public string future { get; set; }
		public string frontier { get; set; }
		public string modern { get; set; }
		public string legacy { get; set; }
		public string pauper { get; set; }
		public string vintage { get; set; }
		public string penny { get; set; }
		public string commander { get; set; }
		[JsonProperty("1v1")]
		public string _1v1 { get; set; }
		public string duel { get; set; }
		public string brawl { get; set; }
	}
	public class MagicCardRelatedUris
	{
		public Uri gatherer { get; set; }
		public Uri tcgplayer_decks { get; set; }
		public Uri edhrec { get; set; }
		public Uri mtgtop8 { get; set; }
	}
	public class MagicCardPurchaseUris
	{
		public Uri amazon { get; set; }
		public Uri ebay { get; set; }
		public Uri tcgplayer { get; set; }
		public Uri magiccardmarket { get; set; }
		public Uri cardhoarder { get; set; }
		public Uri card_kingdom { get; set; }
		public Uri mtgo_traders { get; set; }
		public Uri coolstuffinc { get; set; }
	}

	public class MagicCardFaces
	{
		public string name { get; set; }
		public string mana_cost { get; set; }
		public string type_line { get; set; }
		public string printed_type_line { get; set; }
		public string oracle_text { get; set; }
		public string printed_text { get; set; }
		public string[] colors { get; set; }
		public string flavor_text { get; set; }
		public Guid illustration_id { get; set; }
		public MagicCardImageUris image_uris { get; set; }
	}
}
