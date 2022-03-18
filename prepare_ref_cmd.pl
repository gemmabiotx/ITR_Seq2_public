#!/bin/env perl
# Prepare sh script for mapping ITR-trimmed reads to given reference genome database, using chosen aligner
our $VERSION = v1.1;
our $ENV_FILE = 'set_ref_env.sh';

use strict;
use warnings;
use lib '/project/gtplab/pipeline/ITR_Seq';
use MiSeqITRSeqExpDesign;

my $usage = "Usage: perl $0 DESIGN-FILE BASH-OUTFILE";
my $sh_path = '/bin/bash';
my $vec_anno_script = 'get_vector_seq_anno.pl';
my $samtools = 'samtools';
my $bedtools = 'bedtools';

my $infile = shift or die $usage;
my $outfile = shift or die $usage;
my $design = new MiSeqITRSeqExpDesign($infile);
my $NUM_PROC = $design->get_global_opt('NUM_PROC');
my $BASE_DIR = $design->get_global_opt('BASE_DIR');
my $VECTOR_DIR = $design->get_global_opt('VECTOR_DIR');
my $SCRIPT_DIR = $design->get_global_opt('SCRIPT_DIR');
#my $DEMUX_DIR = $design->get_global_opt('DEMUX_DIR');
my $WORK_DIR = $design->get_global_opt('WORK_DIR');
#my $UMI_LEN = $design->get_global_opt('UMI_LEN');

# check required directories
if(!(-e $BASE_DIR && -d $BASE_DIR)) {
	print STDERR "Error: BASE_DIR $BASE_DIR not exists\n";
	exit;
}

if(!(-e $VECTOR_DIR && -d $VECTOR_DIR)) {
	print STDERR "Error: VECTOR_DIR $VECTOR_DIR not exists\n";
	exit;
}

if(!(-e $SCRIPT_DIR && -d $SCRIPT_DIR)) {
	print STDERR "Error: SCRIPT_DIR $SCRIPT_DIR not exists\n";
	exit;
}

if(!(-e $WORK_DIR)) {
	print STDERR "Error: WORK_DIR $WORK_DIR not exists, creating now\n";
  mkdir($WORK_DIR, 0750) || die "Unable to mkdir $WORK_DIR: $!\n";
}

open(OUT, ">$outfile") || die "Unable to write to $outfile: $!";
# write header
print OUT "#!$sh_path\n";
# set env
print OUT "source $SCRIPT_DIR/$ENV_FILE\n\n";

my %sample_seen;
foreach my $sample ($design->get_sample_names()) {
	if(!exists $sample_seen{$sample}) {
# prepare get vector seq and annotation cmd
		{
			my $in = $design->sample_opt($sample, 'vector_file');
			my $seq_out = $design->get_sample_vec_seq($sample);
			my $anno_out = $design->get_sample_vec_anno($sample);
			my $cmd = "$SCRIPT_DIR/$vec_anno_script $VECTOR_DIR/$in $VECTOR_DIR/$seq_out $VECTOR_DIR/$anno_out";
			if(!(-e "$VECTOR_DIR/$seq_out" && -e "$VECTOR_DIR/$anno_out")) {
				print OUT "$cmd\n";
			}
			else {
				print STDERR "Warning: vector seq and annotation file exist, won't override\n";
				print OUT "# $cmd\n";
			}
		}

# prepare get masked seq, index and db cmd
		{
			my $aligner = $design->sample_opt($sample, 'aligner');
			my $align_opts = $design->sample_opt($sample, 'align_opts');
			my $in = $design->get_sample_vec_seq($sample);
			my $anno = $design->get_sample_vec_anno($sample);
			my $out = $design->get_sample_vec_seq_masked($sample);
			my $dbname = $design->get_sample_vec_dbname($sample);

      # add maskfasta cmd
			my $cmd = "$bedtools maskfasta -fi $VECTOR_DIR/$in -bed <(cat $VECTOR_DIR/$anno | grep -E 'ITR|repeat_region|inverted tandem repeat') -fo $VECTOR_DIR/$out";

      # add faidx cmd
      $cmd .= "\n$samtools faidx $VECTOR_DIR/$out";

      # add build db cmd
			if($aligner eq 'bowtie2') {
				$cmd .= "\nbowtie2-build $VECTOR_DIR/$out $VECTOR_DIR/$dbname"; # add build cmd
			}
			else {
				print STDERR "Error: Unsupported aligner '$aligner'\n";
				exit;
			}

			if(!-e "$VECTOR_DIR/$out") {
				print OUT "$cmd\n";
			}
			else {
				print STDERR "Warning: vec seq masked file exists, won't override\n";
				$cmd =~ s/\n/\n# /sg; # comment out to intermediate lines
				print OUT "# $cmd\n";
			}
		}

	} # end if
  print OUT "\n";
  $sample_seen{$sample}++;
}

close(OUT);
# change to exacutable
chmod 0750, $outfile;