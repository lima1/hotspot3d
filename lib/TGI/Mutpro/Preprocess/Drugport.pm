package TGI::Mutpro::Preprocess::Drugport;
#
#----------------------------------
# $Authors: Beifang Niu 
# $Date: 2014-01-14 14:34:50 -0500 (Tue Jan 14 14:34:50 CST 2014) $
# $Revision:  $
# $URL: $
# $Doc: $ drugport database processing module
#----------------------------------
#
use strict;
use warnings;

use Carp;
use Cwd;
use Getopt::Long;
use LWP::Simple;
use LWP::UserAgent;
our $ua = LWP::UserAgent->new;
$ua->env_proxy; # initialize from environment variables
use IO::File;
use FileHandle;

sub new {
    my $class = shift;
    my $this = {};
    $this->{'output_file'} = 'drugport_results';
    $this->{'pdb_file_dir'} = undef; 
    $this->{'stat'} = undef;
    $this->{'page'} = "";
    bless $this, $class;
    $this->process();
    return $this;
}

sub process {
    my $this = shift;
    my ( $help, $options );
    unless( @ARGV ) { die $this->help_text(); };
    $options = GetOptions (
        'pdb-file-dir=s'  => \$this->{'pdb_file_dir'},
        'output-file=s' => \$this->{'output_file'},
        'help' => \$help,
    );
    if ( $help ) { print STDERR help_text(); exit 0; };
    unless( $options ) { die $this->help_text(); };
    unless( $this->{'output_file'} ne 'drugport_results' ) {
		warn "No output file given. Writing DrugPort results to $this->{'output_file'} !\n";
	}
    unless( $this->{'pdb_file_dir'} and (-e $this->{'pdb_file_dir'})) {
		warn " $_ does not exist ! \n";
		die $this->help_text();
	}
    #### processing ####
    # parse drugport database
    # drug name and ids
    my %drug_hash = ();
    my $appdrugs_url = "http://www.ebi.ac.uk/thornton-srv/databases/drugport/data/appdrugs_pdb.dat";
    my $req = HTTP::Request->new(GET => $appdrugs_url);
    $this->{'page'} = $ua->request($req)->content;
    unless( $this->{'page'} ) { die "can not access drugport database file $! \n"; }
    my ($drug, $did);
    map { @_ = split / /; if ( /^GENERIC_NAME/ ) { $drug = $_[1] }; if ( /^DRUGNAME_ID/ ) { $did = $_[1]; $drug_hash{$did}{'name'} = $drug } } split /\n/, $this->{'page'};
    my $fhout = new FileHandle;
    unless( $fhout->open("> $this->{'output_file'}") ) { die "Could not open output file to write !\n" };
    map { 
        my ( $content, $id, $drug_name, );
        $content = ""; $id = $_;
        $drug_name = $drug_hash{$id}{'name'};
        $content .= $drug_name."\t".$id."\t";
        print STDOUT $drug_name."\t".$id."\n";
        my ($t2n) = $_ =~ /(\d\d)$/;
        my $drugdata_url = "http://www.ebi.ac.uk/thornton-srv/databases/drugport/drugs/$t2n/$_/database.dat";
        my $req2 = HTTP::Request->new(GET => $drugdata_url);
        $this->{'page'} = $ua->request($req2)->content;
        unless( $this->{'page'} ) { die "can not access drug data file $! \n"; }
        my @filter = grep /^HET_GROUP|^TARGET_PDB_ID|^TARGET_CHAIN_ID|^TARGET_DRUG_IN_PDB|^UNASSIGNED_PDB_ID|^UNASSIGNED_CHAIN_ID/, split /\n/, $this->{'page'};
        my ( $het, %ss, %unified, @t, $name, $index, $chain, );
        $het = ""; %ss = (); %unified = (); 
        map { 
            if (/^HET_GROUP/) { 
                @t = split / /; $het = $t[1]; 
            } elsif ( /^UNASSIGNED/ ) { 
                @t = split / /; 
                ($name, $index) = $t[0] =~ /(\w+_\w+_\w+)\[(\d+)\]/; 
                $chain = $t[1]; 
                $unified{$index}{$name} = $t[1]; 
            } else { 
                @t = split / /; 
                $t[0] =~ /(.*?)\[(\d+)\]\[(\d+)\]/; 
                $name = $1; 
                $index = $2."_".$3; 
                $chain = $t[1]; $ss{$index}{"TARGET_DRUG_IN_PDB"} = "NA"; 
                $ss{$index}{$name} = $t[1]; 
            } 
        } @filter;

        $content .= $het."\t"; 
        my ( $target, $nottarget, $unsigned, );
        $target = $nottarget = $unsigned = "";
        map { 
            if ( $ss{$_}{"TARGET_DRUG_IN_PDB"} eq "TRUE" ) { 
                $target .= join("\|", $ss{$_}{"TARGET_PDB_ID"}, $ss{$_}{"TARGET_CHAIN_ID"}).","; 
            } else {
                if ( $ss{$_}{"TARGET_PDB_ID"} and $ss{$_}{"TARGET_CHAIN_ID"} ) {
                    $nottarget .= join("\|", $ss{$_}{"TARGET_PDB_ID"}, $ss{$_}{"TARGET_CHAIN_ID"}).",";
                }
            } 
        } keys %ss; 
        chop($target); chop($nottarget); 
        if ($target) { $content .= $target."\t"; } else { $content .= "NULL\t" }; 
        if ($nottarget) { $content .= $nottarget."\t"; } else { $content .= "NULL\t" }; 
        map {
            if ( $unified{$_}{"UNASSIGNED_PDB_ID"} and $unified{$_}{"UNASSIGNED_CHAIN_ID"} ) {
                $unsigned .= join("\|", $unified{$_}{"UNASSIGNED_PDB_ID"}, $unified{$_}{"UNASSIGNED_CHAIN_ID"}).",";
            } 
        } keys %unified; 
        chop( $unsigned ); 
        if ( $unsigned ) { $content .= $unsigned."\n"; } else { $content .= "NULL\n" };
        ######
        my $temp_content = "";
        chomp( $content );
        @t = split /\t/, $content;
        $het = $t[2];
        #print join("\t", @t[0..2]); print "\t";
        $temp_content .= join("\t", @t[0..2])."\t";
        $het =~ s/ //g;
        map {
            #print $_."\t";
            $temp_content .= $_."\t";
            my @buf1 = ();
            unless( $_ =~ /NULL/ ) {
                map { 
                    my ($pdb, $chain) = $_ =~ /(\w+)\|(\w+)/;
                    $pdb =~ s/ //g; $chain =~ s/ //g;
                    my $t_pdb_f = $this->{'pdb_file_dir'} . uc( $pdb ). ".pdb";
                    my $pdb_file_name = uc( $pdb ). ".pdb";
                    my @pdb_infor = ();
                    if ( -e $t_pdb_f ) {
                        @pdb_infor = map{ chomp; $_ } `cat $t_pdb_f`;
                    } else {
                        my $pdb_url = "http://www.rcsb.org/pdb/files/$pdb_file_name";
                        my $req = HTTP::Request->new(GET => $pdb_url);
                        $this->{'page'} = $ua->request($req)->content;
                        if ( $this->{'page'} ) {
                            @pdb_infor = split /\n/, $this->{'page'};
                        } else { warn "can not access pdb file $! \n"; } 
                    }
                    foreach ( @pdb_infor ) {
                        chomp; 
                        next if ($_ !~ /^HETATM/); 
                        my @cols = split //, $_; 
                        my $t_het = join( "", @cols[17..19] ); 
                        my $t_chain = $cols[21]; 
                        my $t_loc = join( "", @cols[22..25] ); 
                        $t_het =~ s/ //g; 
                        $t_loc =~ s/ //g; 
                        if ( ($t_chain eq $chain) and ( $t_het eq $het ) and ( $t_loc !~ /-/ ) ) { 
                            my $t_con = join("\|", $pdb, $chain, $t_loc, $t_het); 
                            push ( @buf1, $t_con ); last 
                        } 
                    }
                } split /,/, $_;
            }
            if ( @buf1 ) { $temp_content .= join(",", @buf1) } else { $temp_content .= "NULL" }
            $temp_content .= "\t";
        } @t[3..5];
        chop( $temp_content );
        $temp_content .= "\n";
        $fhout->print( $temp_content );
    } keys %drug_hash;

}

sub help_text {
    my $this = shift;
        return <<HELP

Usage: hotspot3d drugport [options]

                             REQUIRED
--pdb-file-dir               PDB file directory 

                             OPTIONAL
--output-file                Output file of drugport parsing, default: drugport_results

--help                       this message

HELP

}

1;

