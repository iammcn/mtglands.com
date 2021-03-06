#!/usr/bin/perl

use utf8;
use v5.10;
use strict;
use warnings;

use Config;
use Date::Parse;
use Data::Dumper;
use File::Copy;
use HTML::Escape   qw( escape_html );
# https://metacpan.org/pod/HTML::Escape
use HTTP::Request;
use IO::Uncompress::Unzip qw( unzip $UnzipError );
use JSON::XS;
use List::AllUtils qw( first uniq any none sum max );
# https://metacpan.org/pod/List::AllUtils
# https://metacpan.org/release/List-SomeUtils
# https://metacpan.org/pod/List::UtilsBy
use LWP;
use Scalar::Util   qw( weaken );
use YAML::XS       qw( LoadFile );

$| = 1;

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

##################################################################################################

### XXX: This is a (slight) security risk.  Move these outta here...
my $BASE_DIR  = $ARGV[0];
my $WWW_CHOWN = 'www-data:www-data';
my $WWW_CHMOD = 0660;

say "Loading land types data...";
my %LAND_TYPES      = %{ LoadFile('conf/land_types.yml')  };
my @LAND_CATEGORIES = (
    'Main', 'Color Identity', 'Mana Pool', 'Supertypes', 'Subtypes', 'Restricted', 'Banned', 'Other'  # in order
);
my @MPG_ORDER = (
    'Manaless', 'Colorless', 'Monocolor', 'Dual Colors', 'Tri-Colors', 'Any Color',
    'Commander Colors', 'Conditional'
);

say "Loading color types data...";
my %COLOR_TYPES = %{ LoadFile('conf/color_types.yml') };
my %COLOR_NAMES = ();
foreach my $id (sort keys %COLOR_TYPES) {
    my $color_type = $COLOR_TYPES{$id};
    $COLOR_NAMES{ $color_type->{name} } = $color_type;
    $color_type->{id} = $id;

    # Figure out a true color identity, including all of its subsets/supersets
    $color_type->{subsets}   = {};
    foreach my $other_id (sort keys %COLOR_TYPES) {
        my $passes_check = 1;
        foreach my $C (split //, $other_id) {
            $passes_check = 0 unless $id =~ /$C/;
        }
        next unless $passes_check;

        $color_type->{subsets}{$other_id} = $COLOR_TYPES{$other_id};
        weaken $color_type->{subsets}{$other_id};

        $COLOR_TYPES{$other_id}{supersets}    //= {};
        $COLOR_TYPES{$other_id}{supersets}{$id} = $color_type;
        weaken $COLOR_TYPES{$other_id}{supersets}{$id};
    }
}

my $ua = LWP::UserAgent->new;
$ua->agent('MTGLands.com/1.0 '.$ua->_agent);

##################################################################################################

# NOTE: We are using the AllPrintings.json data because it has more fields about the sets that might be
# useful.  It's larger, but is especially nice for being able to use the latest card printed.
#
# https://mtgjson.com/downloads/all-files/
# https://mtgjson.com/api/v5/AllPrintings.json.zip

### Load up the MTG JSON data ###

say "Loading JSON data...";

# Download it if we have to
my $json_filename = 'AllPrintings.json';
if (not -e $json_filename) {
    unless (-s $json_filename && -M $json_filename < 1) {
        my $url = "https://mtgjson.com/api/v5/$json_filename.zip";
        print "    $url";

        my $req = HTTP::Request->new(GET => $url);
        my $res = $ua->request($req);

        if ($res->is_success) {
            my $zip_data = $res->content;

            print " => $json_filename";

            open my $json_fh, '>', $json_filename or die "Can't open $json_filename: $!";
            unzip \$zip_data, $json_fh            or die "Can't unzip $json_filename: $UnzipError";
            close $json_fh;

            print "\n";
        }
        else {
            die "Can't download MTG JSON file: ".$res->status_line."\n";
        }
    }
}

my $json = JSON::XS->new->utf8;  # raw data needs to be undecoded UTF-8

open my $json_fh, '<', $json_filename or die "Can't open $json_filename: $!";
$/ = undef;
my $raw_json = <$json_fh>;
close $json_fh;

say "Decoding JSON data...";
my %MTG_DATA = %{ $json->decode($raw_json)->{data} };
undef $raw_json;

### Find lands ###

# This just adds in epoch dates here for sorting
foreach my $set_data (values %MTG_DATA) {
    $set_data->{releaseDate} = str2time($set_data->{releaseDate});
}

my %LAND_DATA;

say "Searching for lands...";
foreach my $set (
    # sort by release date
    sort { $MTG_DATA{$b}{releaseDate} <=> $MTG_DATA{$a}{releaseDate} }
    # in cases of ties, favor promos over standard sets
    sort { ($MTG_DATA{$a}{type} =~ /core|expansion|reprint/) <=> ($MTG_DATA{$b}{type} =~ /core|expansion|reprint/) }
    keys %MTG_DATA
) {
    my $set_data = $MTG_DATA{$set};

    # almost all of these had paper analogues
    next if $set_data->{isOnlineOnly} && $set_data->{isOnlineOnly} eq 1;
    next if $set_data->{isFoilOnly} && $set_data->{isFoilOnly} eq 1;

    # exclude promo sets
    next if $set_data->{type} eq 'promo';

    # none of the playtest cards
    next if $set_data->{code} eq 'CMB1';
    # no cards from Shandalar
    next if $set_data->{code} eq 'PAST';
    # no Secret Lairs
    next if $set_data->{code} eq 'SLD';
    next if $set_data->{code} eq 'SLU';

    foreach my $card_data (@{ $set_data->{cards} }) {
        next unless first { $_ eq 'Land' } @{$card_data->{types}};  # only interested in lands
        next if $card_data->{rarity} eq 'Special';                  # only interested in legal cards
        next if $card_data->{borderColor} eq 'silver';              # no Un-sets
        next if $card_data->{borderColor} eq 'gold';                # don't show gold border prints

        my $name = $card_data->{name};
        next if $LAND_DATA{$name};  # only add in the most recent entry

        $LAND_DATA{$name} = $card_data;

        #if ($name eq 'Spire of Industry') {
        #    warn Dumper $card_data;
        #    local $Data::Dumper::Maxdepth = 1;
        #    warn Dumper $set_data;
        #}

        # Extra data to add
        $card_data->{setData} = $set_data;
        weaken $card_data->{setData};
        $card_data->{setName}     = $set_data->{name};
        $card_data->{printingStr} = join ',', @{$card_data->{printings}};

        # Color identity in a easier WUBRG string
        my $color_id = '';
        foreach my $L (split //, 'WUBRG') {
            $color_id .= $L if first { $_ eq $L } @{ $card_data->{colorIdentity} };
        }
        $card_data->{colorIdStr} = $color_id;

        # Legalities in an couple of easier-to-use strings
        $card_data->{legal}      = '';
        $card_data->{restricted} = '';
        $card_data->{banned}     = '';

        foreach ("vintage", "legacy", "modern", "standard", "commander", "brawl", "pioneer") {
            my $F = uc substr($_, 0, 1);

            if ($card_data->{legalities}->{$_}) {
                if ($card_data->{legalities}->{$_} eq "Legal") {
                    $card_data->{legal} .= $F;
                }
                if ($card_data->{legalities}->{$_} eq "Restricted") {
                    $card_data->{restricted} .= $F;
                }
                if ($card_data->{legalities}->{$_} eq "Banned") {
                    $card_data->{banned} .= $F;
                }
            }
        }

        # Mark any new cards
        $card_data->{isNew} =
            $set_data->{releaseDate} >= (time - 365 * 24*60*60) &&  # released at most a year ago
            scalar @{$card_data->{printings}} == 1                  # only in this set
            ? 1 : 0
        ;

        # scryfall.com is our base source for large images and URLs
        my $card_num = $card_data->{number};
        my $card_set = $set_data->{code};

        # ensure card_num only contains valid characters (can contin '*')
        if ($card_num =~ /([0-9a-zA-Z]+)/g) {
            $card_num = $1;
        }
        else {
            warn "Invalid number '$card_num'!\n";
        }

        if ($card_num && $card_set) {
            $card_data->{infoURL}       = sprintf 'http://scryfall.com/card/%s/%s', lc $card_set, lc $card_num;
            $card_data->{localLgImgURL} = sprintf 'img/large/%s-%s.jpg',            lc $card_set, lc $card_num;
            $card_data->{localSmImgURL} = sprintf 'img/small/%s-%s.jpg',            lc $card_set, lc $card_num;
        }
        else {
            warn "Could not find card number for '$name'!\n" unless $card_num;
            warn "Could not find card set for '$name'!\n"    unless $card_set;
        }
    }
}

### Fill in the rest of %LAND_TYPES data ###

say "Filling in land type data...";
foreach my $category (@LAND_CATEGORIES) {
    my $category_data = $LAND_TYPES{$category};
    next unless $category_data;

    foreach my $type (sort keys %$category_data) {
        my $type_data = $category_data->{$type};

        my @matching_data = $type_data;
        push @matching_data, @{ $type_data->{matching} } if $type_data->{matching};

        foreach my $matching_data (@matching_data) {
            # Create a new RegExp based on the example card
            if ($matching_data->{example} && !$matching_data->{text_re}) {
                my $name      = $matching_data->{example};
                my $land_data = $LAND_DATA{$name} || die "Can't find example land card '$name' in MTG JSON for '$type'!";
                next unless exists $land_data->{text};

                my $base_re   = $land_data->{text};
                my $quotename = quotemeta $name;
                $base_re =~ s/
                    # find its own card name
                    (?:(?<=\W)|\A) $quotename (?=\W)
                /⦀name⦀/gx;  # use U+2980 as a "percent-code"

                $base_re = quotemeta $base_re;
                $base_re =~ s/\\⦀/⦀/g;     # revert backslashes of code char
                $base_re =~ s/\\ / /g;     # space escaping is excessive
                $base_re =~ s/\\\n/\\R/g;  # use '\R' for newline escaping

                ### XXX: This is a whole lot of backslashes, because of the quotemeta...
                $base_re =~ s/
                    # mana color symbols
                    (?<=\\\{) [WURGB] (?=\\\})
                /[WURGB]/gx;
                $base_re =~ s!
                    # split mana color symbols
                    (?<=\\\{) [WURGB0-9]\\/[WURGB0-9] (?=\\\})
                ![WURGB0-9]/[WURGB0-9]!gx;
                $base_re =~ s!
                    # Phyrexian mana color symbols
                    (?<=\\\{) [WURGB0-9]P (?=\\\})
                ![WURGB0-9]P!gx;
                $base_re =~ s/
                    # find all basic land types, even with 'a' or 'an'
                    (?:(?<=\W)|^) (?:an?\s)? (?:Plains|Island|Mountain|Forest|Swamp) (?=\W)
                /(?:an? )?(?:Plains|Island|Mountain|Forest|Swamp)/gx;
                $base_re =~ s/
                    # find all colors
                    (?:(?<=\W)|^) (?:[Ww]hite|[Bb]lue|[Bb]lack|[Rr]ed|[Gg]reen) (?=\W)
                /(?:[Ww]hite|[Bb]lue|[Bb]lack|[Rr]ed|[Gg]reen)/gx;

                $matching_data->{text_re} = "\\A$base_re\\z";
            }
        }
    }
}

### Categorize each land card ###

say "Categorizing lands...";

foreach my $name (sort keys %LAND_DATA) {
    my $land_data = $LAND_DATA{$name};

    $land_data->{landTags} //= {};

    # Match the various land categories, each with its own specific type
    foreach my $category (@LAND_CATEGORIES) {
        my $category_data = $LAND_TYPES{$category};
        next unless $category_data;

        foreach my $type (sort keys %$category_data) {
            my $type_data = $category_data->{$type};

            my @matching_data = $type_data;
            push @matching_data, @{ $type_data->{matching} } if $type_data->{matching};

            my $does_match = 0;
            MATCH_LOOP: foreach my $matching_data (@matching_data) {
                foreach my $match_type ('', '_neg') {
                    foreach my $re_key (sort grep { /\w+_re$match_type$/ } keys %$matching_data) {
                        my $key = $re_key;
                        $key =~ s/_re$match_type$//;

                        unless (exists $land_data->{$key}) {
                            $does_match = 0;
                            next MATCH_LOOP;
                        }

                        my $re = $matching_data->{$re_key};
                        $re =~ s/⦀$_⦀/$land_data->{$_}/ge for keys %$land_data;

                        #if ($type eq 'Keyword Lands' && $name eq 'Tolaria West') {
                        #    warn "Currently matching: $category / $type / $does_match\n";
                        #    warn "RE$match_type: $re\n";
                        #    warn "$key: $land_data->{$key}\n";
                        #}

                        # each *_re* line must match
                        $does_match = $match_type eq '_neg' ?
                            $land_data->{$key} !~ /$re/i :
                            $land_data->{$key} =~ /$re/i
                        ;

                        next MATCH_LOOP unless $does_match;
                    }
                }

                last MATCH_LOOP if $does_match;  # any matching block will work
            }
            next unless $does_match;

            # If we got this far, it must have passed
            $land_data->{landTags}{$category} //= [];
            push @{ $land_data->{landTags}{$category} }, $type;

            # Remove dupes
            $land_data->{landTags}{$category} = [ uniq @{ $land_data->{landTags}{$category} } ];

            # Add to the card list within the type
            $type_data->{cards} //= {};
            $type_data->{cards}{$name} = $land_data;
            weaken $type_data->{cards}{$name};

            # The Main category usually has add-ons to clarify the other categories
            if ($type_data->{tags}) {
                foreach my $tag_cat (sort keys %{ $type_data->{tags} }) {
                    $land_data->{landTags}{$tag_cat} //= [];
                    push @{ $land_data->{landTags}{$tag_cat} }, $type_data->{tags}{$tag_cat};
                }
            }
        }
    }

    # Color identity
    my $color_type = $land_data->{colorIdType} = $COLOR_TYPES{ $land_data->{colorIdStr} };
    $land_data->{landTags}{'Color Identity'} = [
        uniq grep { defined } map { $color_type->{$_} } qw/ type subtype name /
    ];

    # Supertypes / Subtypes
    $land_data->{landTags}{Supertypes} = $land_data->{supertypes};
    $land_data->{landTags}{Subtypes}   = $land_data->{subtypes};

    # Restricted / Banned
    $land_data->{landTags}{Restricted} = [ $land_data->{restricted} ] if $land_data->{restricted};
    $land_data->{landTags}{Banned}     = [ $land_data->{banned}     ] if $land_data->{banned};

    # Make sure each land matches correctly
    foreach my $category ('Main', 'Mana Pool', 'Color Identity') {
        ### XXX: Too many of these right now...
        next if $category eq 'Main';

        warn "Didn't match $category for land card '$name'!\n" unless $land_data->{landTags}{$category};
    }

    # If it didn't match a main category, put it in an unsorted one
    unless ($land_data->{landTags}{Main}) {
        $land_data->{landTags}{Main} = [ 'Other Lands' ];
    }

    # Add the other auto-generated tags into %LAND_TYPES, too
    foreach my $category (@LAND_CATEGORIES) {
        next unless $land_data->{landTags}{$category};

        foreach my $type (@{ $land_data->{landTags}{$category} }) {
            my $type_data = $LAND_TYPES{$category}{$type} //= {};
            $type_data->{name}       //= $type;
            $type_data->{cards}      //= {};
            $type_data->{cards}{$name} = $land_data;

        }
    }
}

### Creating download images file

say "Creating download images file...";

my $filename = "$BASE_DIR/img/TEMP_IMAGE_DOWNLOAD_LIST.txt";

open my $jpeg_fh, '>', $filename or die "Can't open $filename: $!";

foreach my $name (sort keys %LAND_DATA) {
    my $land_data = $LAND_DATA{$name};

    my $isTransformCard = "false";
    if ($land_data->{otherFaceIds}) {
        $isTransformCard = "true";
    }

    # unfortunate custom code for meld land and transform into creature land
    if ($land_data->{name} eq "Hanweir Battlements // Hanweir, the Writhing Township"
        || $land_data->{name} eq "Westvale Abbey // Ormendahl, Profane Prince") {
        $isTransformCard = "false";
    }

    printf $jpeg_fh "%s %s %s %s\n", $land_data->{identifiers}->{scryfallId}, $land_data->{localLgImgURL}, $land_data->{localSmImgURL}, $isTransformCard;
}

close $jpeg_fh;

### Build HTML pages based on the lesser categories, with the Main categories looped on each page

say "Copying image/style/script files...";
foreach my $filename (glob "script/* style/* img/*") {
    copy($filename, "$BASE_DIR/$filename");
    chmodown("$BASE_DIR/$filename");
}

say "Creating HTML...";
foreach my $category (@LAND_CATEGORIES) {
    my $category_data = $LAND_TYPES{$category};
    next unless $category_data;

    foreach my $first_type (sort keys %$category_data) {
        my $first_type_data = $category_data->{$first_type};
        my $html_filename   = simplify_name($category).'-'.simplify_name($first_type).'.html';

        $first_type_data->{headerSuffix} //= '';
        my $land_type_title = land_type_label($category, $first_type);
        my $html_fh = start_html(
            $html_filename,
            "Lands filtered by $land_type_title".$first_type_data->{headerSuffix},
            $land_type_title
        );

        foreach my $main_type (
            sort  { sort_mpg_avg($LAND_TYPES{Main}{$b}) <=> sort_mpg_avg($LAND_TYPES{Main}{$a}) }
            sort
            keys %{ $LAND_TYPES{Main} }
        ) {
            # For the main category, just display the one type
            if ($category eq 'Main') {
                next unless $first_type eq $main_type;
            }

            my $main_type_data = $LAND_TYPES{Main}{$main_type};

            # Build a "fake" types hash with the filtered results
            my $filter_type_data = {
                cards     => {
                    map   { $_ => $main_type_data->{cards}{$_} }
                    grep  { $first_type_data->{cards}{$_} }
                    keys %{ $main_type_data->{cards} }
                },
                alt_names => $main_type_data->{alt_names},
            };

            next unless %{ $filter_type_data->{cards} };

            say $html_fh build_type_html_body($main_type, $filter_type_data);
        }

        end_html($html_fh);
    }
}

# Also create an 'all.html' file with everything

my $html_fh = start_html('all.html', 'All lands, unfiltered', 'All lands');

foreach my $type (
    sort  { sort_mpg_avg($LAND_TYPES{Main}{$b}) <=> sort_mpg_avg($LAND_TYPES{Main}{$a}) }
    sort
    keys %{ $LAND_TYPES{Main} }
) {
    say $html_fh build_type_html_body($type, $LAND_TYPES{Main}{$type});
}

end_html($html_fh);

# Finally, create an 'index.html' page

$html_fh = start_html(
    'index.html' => 'All of the lands, all up-to-date, all categorized, all dynamically generated'
);

say $html_fh build_index_html_body();

end_html($html_fh);

### Fin

exit;

##################################################################################################

sub chmodown {
    # don't need to do this in windows
    if (not $Config{'osname'} eq 'MSWin32') {
        my ($filename) = @_;
        my ($uid, $gid) = split /:/, $WWW_CHOWN, 2;
        $uid = getpwnam($uid);
        $gid = getgrnam($gid);

        chmod $WWW_CHMOD, $filename or die "Can't chmod $filename: $!";
        chown $uid, $gid, $filename or die "Can't chown $filename: $!";
    }
}

sub sort_mpg_avg {
    my ($type_data) = @_;
    my $total = scalar values %{ $type_data->{cards} };
    return -1 unless $total;
    return -1 if $type_data->{name} eq 'Other Lands';

    my $i = 0;
    my %mpg2sort = map { $_ => $i++ } @MPG_ORDER;

    my $sum = sum(
        map     {
            my @tags = @{ $_->{landTags}{'Mana Pool'} };
            max( map { $mpg2sort{$_} } @tags );
        }
        values %{ $type_data->{cards} }
    );

    return $sum / $total;  # avg MP generation
}

sub sort_color_id {
    my ($ci) = @_;
    return 0 if $ci eq '';

    # Goofy, but it works
    my $num = $ci;
    $num =~ tr/WUBRG/12345/;

    # Append a final color subtype to the number
    my $len     = length $ci;
    my $subtype = $COLOR_TYPES{$ci}{subtype} || '';

    my %subtype_scores = (
        Allied => 1,
        Enemy  => 2,
        Shard  => 3,
        Wedge  => 4,
    );

    if    ($len >= 4) {
        $num += 900_000;  # supercedes all else
    }
    elsif ($len >= 2 && $subtype) {
        $num += $subtype_scores{$subtype} * 100_000;
    }

    return $num;
}

sub simplify_name {
    my ($txt) = @_;
    $txt = lc $txt;
    $txt =~ s/\W+//g;
    return $txt;
}

sub land_type_label {
    my ($category, $type) = @_;

    # Special category prefixes
    my $label =
        $category eq 'Mana Pool'         ? 'MP: ' :
        $category =~ /^Color Identity/   ? 'CI: ' :
        $category =~ /Restricted|Banned/ ? "$category: " :
        ''
    ;

    # compose a label with mana icons
    my $color_type = $COLOR_NAMES{$type};
    if ($category =~ /^Color Identity/ && $color_type) {
        my $id = $color_type->{id} || 'C';
        $label .= "<span class=\"mana s".lc($_)."\"></span>" for split //, $id;
        $label .= ' ';
    }
    $label .= escape_html($type);

    return $label;
}

sub land_type_link {
    my ($category, $type) = @_;

    my $label = land_type_label($category, $type);

    # figure out the right link for this label
    my $link = simplify_name($category).'-'.simplify_name($type).'.html';

    return "<a href=\"$link\" class=\"label tag-".simplify_name($category)."\">$label</a> ";
}

my $OPENED_FILENAME;
sub start_html {
    my ($filename, $subheader, $subtitle) = @_;

    print "    $filename";
    open my $fh, '>:encoding(UTF-8)', "$BASE_DIR/$filename" or die "Can't open $filename: $!";

    say $fh build_html_header($subheader, $subtitle);

    # XXX: Lazy hack for chmodown in end_html
    $OPENED_FILENAME = $filename;

    return $fh;
}

sub build_html_header {
    my ($subheader, $subtitle) = @_;

    if ($subtitle) {
        $subtitle =~ s!</?span.*?>!!g;  # no HTML in title
        $subtitle =~ s!\s+! !g;
    }

    my $description = $subheader;
    $description =~ s!</?span.*?>!!g;  # no HTML in description
    $description =~ s!\s+! !g;

    my $html = <<'END_HTML';
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8" />
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
END_HTML
    $html .= "<meta name=\"description\" content=\"MTGLands.com: $description\" />\n";

    # NOTE: The Google Analytics code still needs to be in the HEAD tag...
    $html .= <<'END_HTML';
    <meta name="keywords" content="mtg,lands,dual lands,shock lands,pain lands,manlands" />
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous" />
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.3/css/select2.min.css" />
    <link rel="stylesheet" href="style/main.css" />
    <link rel="stylesheet" href="style/mana.css" />
    <script>
        (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
        (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
        m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
        })(window,document,'script','https://www.google-analytics.com/analytics.js','ga');

        ga('create', 'UA-86684306-1', 'auto');
        ga('send', 'pageview');
    </script>
END_HTML
    $html .= $subtitle ?
        "<title>MTG Lands - $subtitle</title>\n" :
        "<title>MTG Lands</title>\n"
    ;
    $html .= <<'END_HTML';
</head>
<body>
<form id="form-filters">
    Legality: <select name="legal">
        <option value="all" selected>All cards</option>
END_HTML
    foreach my $format (qw/Vintage Commander Legacy Modern Standard Brawl Pioneer/) {
        my $F = substr($format, 0, 1);
        $html .= "        <option value=\"$F\">Legal in $format</option>\n";
    }
    $html .= <<'END_HTML';
    </select><br>
    Color Identity: <select name="ci">
        <option value="all" selected>All cards</option>
END_HTML
    my $optgroup;
    foreach my $type (
        sort { sort_color_id($a) <=> sort_color_id($b) }
        keys %COLOR_TYPES
    ) {
        my $color_type = $COLOR_TYPES{$type};
        my $id         = $color_type->{id} || 'C';
        my $label      = "$id | ".$color_type->{name};

        # Display optgroups
        unless ($optgroup && $optgroup eq $color_type->{type}) {
            $html .= "        </optgroup>\n" if $optgroup;
            $optgroup = $color_type->{type};
            $html .= "        <optgroup label=\"$optgroup\">\n";
        }

        $html .= "            <option value=\"$id\">$label</option>\n";
    }

    $html .= <<'END_HTML';
        </optgroup>
    </select>
</form>
<h1><a href="/">MTG Lands</a></h1>

END_HTML

    # No HTML escaping, since mana symbols might be in here
    $html .= "\n<h4>$subheader</h4>\n\n" if $subheader;
    $html .= "<hr/>";

    return $html;
}

sub build_type_html_body {
    my ($header, $type_data) = @_;
    return '' unless $type_data->{cards} && %{ $type_data->{cards} };

    my $html = "\n<div class=\"cardsection\">\n";
    $html .= "<h2><a name=\"".simplify_name($header)."\"></a>$header</h2>\n\n";

    if ($type_data->{alt_names}) {
        $html .= "\n<h4>Also known as: ".join(', ', @{$type_data->{alt_names}})."</h4>\n\n";
    }

    $html .= "<div class=\"container\">\n";
    $html .= "<div class=\"row\">\n";

    foreach my $name (
        sort { sort_color_id($LAND_DATA{$a}{colorIdStr}) <=> sort_color_id($LAND_DATA{$b}{colorIdStr}) }
        sort { $LAND_DATA{$b}{setData}{releaseDate} <=> $LAND_DATA{$a}{setData}{releaseDate} }
        sort { $a cmp $b }
        keys %{ $type_data->{cards} }
    ) {
        my $land_data = $LAND_DATA{$name};

        # Figure out the card info tags first
        my $card_info_html = '<div class="cardname">'.escape_html($name)."</div>\n";

        $card_info_html .= '<div class="cardtags">'."\n";
        foreach my $category (@LAND_CATEGORIES) {
            my $category_tags = $land_data->{landTags}{$category};
            next unless $category_tags;

            foreach my $tag (@$category_tags) {
                $card_info_html .= land_type_link($category, $tag);
            }
            $card_info_html .= "\n";
        }
        $card_info_html .= "</div>\n";

        # Add the legalities and color identity to the main card DIV for easy filtering
        my $legal_classes = join ' ', map { "legal-$_" } split //, $land_data->{legal};
        my $ci_class      = 'ci-'.($land_data->{colorIdStr} || 'C');
        $html .= "<div class=\"card $ci_class $legal_classes\">\n";

        # Use two different types of images, depending if it's on a large screen or not
        $html .=
            '<div class="card-sm">'.
            '<a href="'.$land_data->{infoURL}.'">'.
            '<img width="223" height="311" border="0" alt="'.escape_html($name).'" src="'.$land_data->{localSmImgURL}.'"/>'.
            '</a>'.
            $card_info_html.
            "</div>\n"
        ;
        $html .=
            '<div class="card-lg">'.
            '<a href="'.$land_data->{infoURL}.'">'.
            '<img width="312" height="445" border="0" alt="'.escape_html($name).'" src="'.$land_data->{localLgImgURL}.'"/>'.
            '</a>'.
            $card_info_html.
            "</div>\n"
        ;
        $html .= "</div>\n";
    }

    $html .= "</div>\n";
    $html .= "</div>\n";
    $html .= "<hr/>\n";
    $html .= "</div>\n";

    return $html;
}

sub build_index_html_body {
    my $html = '';

    $html .= <<'END_HTML';

<h2><a href="all.html">All Lands</a></h2>

<h2>Main Land Types</h2>

<div class="container">
<div class="row indextags">
END_HTML

    foreach my $type (
        sort  { sort_mpg_avg($LAND_TYPES{Main}{$b}) <=> sort_mpg_avg($LAND_TYPES{Main}{$a}) }
        sort
        keys %{ $LAND_TYPES{Main} }
    ) {
        $html .= land_type_link('Main', $type)."\n";
    }

    $html .= <<'END_HTML';
</div>
</div>

<h2>Color Identity</h2>

<div class="container">
END_HTML

    my (@color_types, @color_subtypes, @color_names);
    foreach my $type (
        sort { sort_color_id($a) <=> sort_color_id($b) }
        keys %COLOR_TYPES
    ) {
        my $color_type = $COLOR_TYPES{$type};

        unless ($color_type->{type} eq 'Four Color') {  # none exist yet...
            push @color_types,    $color_type->{type}    unless $color_type->{type} eq $color_type->{name};
            push @color_subtypes, $color_type->{subtype} if $color_type->{subtype};
            push @color_names,    $color_type->{name};
        }
    }
    @color_types    = uniq @color_types;
    @color_subtypes = uniq @color_subtypes;

    my ($type_html, $subtype_html, $name_html) = ('', '', '');
    $type_html    .= land_type_link('Color Identity', $_)."\n" for @color_types;
    $subtype_html .= land_type_link('Color Identity', $_)."\n" for @color_subtypes;
    $name_html    .= land_type_link('Color Identity', $_)."\n" for @color_names;

    $html .= <<"END_HTML";
<h4>Color Count</h4>
<div class=\"row indextags\">\n$type_html</div>

<h4>Subtypes</h4>
<div class=\"row indextags\">\n$subtype_html</div>

<h4>Identity (Exact)</h4>
<div class=\"row indextags\">\n$name_html</div>
END_HTML

    $html .= <<'END_HTML';
</div>

<h2>Mana Generators</h2>

<div class="container">
<div class="row indextags">
END_HTML

    foreach my $type (@MPG_ORDER) {
        $html .= land_type_link('Mana Pool', $type)."\n";
    }

    $html .= <<'END_HTML';
</div>
</div>

<h2>Card Types</h2>

<div class="container">
<h4>Supertypes</h4>
<div class="row indextags">
END_HTML

    foreach my $type (sort keys %{ $LAND_TYPES{Supertypes} }) {
        $html .= land_type_link('Supertypes', $type)."\n";
    }

    $html .= <<"END_HTML";
</div>

<h4>Subtypes</h4>
<div class=\"row indextags\">
END_HTML

    foreach my $type (sort keys %{ $LAND_TYPES{Subtypes} }) {
        $html .= land_type_link('Subtypes', $type)."\n";
    }

    $html .= <<'END_HTML';
</div>
</div>

<h2>Legalities</h2>

<div class="container">
<h4>Restricted</h4>
<div class="row indextags">
END_HTML

    foreach my $type (sort keys %{ $LAND_TYPES{Restricted} }) {
        $html .= land_type_link('Restricted', $type)."\n";
    }

    $html .= <<"END_HTML";
</div>

<h4>Banned</h4>
<div class=\"row indextags\">
END_HTML

    foreach my $type (sort keys %{ $LAND_TYPES{Banned} }) {
        $html .= land_type_link('Banned', $type)."\n";
    }

    $html .= <<'END_HTML';
</div>
</div>

<h2>Other Types</h2>

<div class="container">
<div class="row indextags">
END_HTML
    foreach my $type (sort keys %{ $LAND_TYPES{Other} }) {
        $html .= land_type_link('Other', $type)."\n";
    }

    $html .= <<'END_HTML';
</div>
</div>

<hr/>

<h2>Awesome MTG/EDH Resources</h2>

<ul>
    <li>Tolarian Community College's Excellent Commander Mana Base videos:</li>
    <ul>
        <li><a href="https://www.youtube.com/watch?v=UleH4wxzONA">5 Color Decks</a></li>
        <li><a href="https://www.youtube.com/watch?v=5DSddyFCqPk">4 Color Decks</a></li>
        <li><a href="https://www.youtube.com/watch?v=ifig4xSp0kA">3 Color Decks</a></li>
        <li><a href="https://www.youtube.com/watch?v=MDc4v7sDaQY">2 Color Decks</a></li>
    </ul>
    <li><a href="http://www.edhrec.com/">EDHREC</a></li>
    <li><a href="http://manabasecrafter.com/">Manabase Crafter</a>, a similar but different kind of
    land/manabase lookup reference</li>
    <li><a href="https://mtgjson.com/">MTG JSON</a>, used to acquire all of the information on this site</li>
</ul>
<hr/>
END_HTML

    return $html;
}

sub build_html_footer {
return <<'END_HTML';
<div class="footer-links">
    <a href="/">Main Index</a> |
    <a href="all.html">All Lands</a> |
    <a href="https://github.com/SineSwiper/mtglands.com">Source</a> |
    <a href="https://github.com/SineSwiper/mtglands.com/issues">Report Issues</a>
</div>

<small class="disclaimer">This website is not produced, endorsed, supported, or affiliated with
Wizards of the Coast, nor any of the sites linked.</small>

</body>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.1.1/jquery.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/select2/4.0.3/js/select2.min.js" async></script>
<script src="script/js.cookie.js" async></script>
<script src="script/main.js" async></script>
</html>
END_HTML
}

sub end_html {
    my ($fh) = @_;

    say $fh build_html_footer();
    close $fh;

    chmodown("$BASE_DIR/$OPENED_FILENAME");
    $OPENED_FILENAME = undef;

    print "\n";
}
