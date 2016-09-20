package illumina_metadataParser;

use strict;
use warnings;

use JSON;
use Carp;

BEGIN {
    use Exporter;

    our @ISA = ('Exporter');

    our @EXPORT = qw(
                        &metadataParse
                   );
}

sub metadataParse(@) {
    my $outputdir_name = shift || return undef;
    my $metadata_file = "$outputdir_name/metadata";
    my $json_conf = do {
        open (my $json_fh, "<:encoding(UTF-8)", $metadata_file) or confess "Can't open $metadata_file";
        local $/;
        <$json_fh>;
    };
    my $config = decode_json($json_conf);
    return ($config);
}

1;
