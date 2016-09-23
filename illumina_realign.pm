package illumina_realign;

use 5.16.0;
use strict;
use warnings;

use File::Basename;
use File::Spec::Functions;

use FindBin;
use lib "$FindBin::Bin";

use illumina_sge;
use illumina_template;

sub runRealignment {

    my $configuration = shift;
    my %opt = %{$configuration};
    my $runName = basename($opt{OUTPUT_DIR});

    say "Running single sample indel realignment for the following BAM-files:";

    my @knownIndelFiles;
    if ($opt{REALIGNMENT_KNOWN}) {
		@knownIndelFiles = split('\t', $opt{REALIGNMENT_KNOWN});
    }

    foreach my $sample (keys $opt{SAMPLES}) {
	    my $bam = $opt{BAM_FILES}->{$sample};
	    (my $flagstat = $bam) =~ s/\.bam/.flagstat/;
	    (my $realignedBam = $bam) =~ s/\.bam/\.realigned\.bam/;
	    (my $realignedBai = $bam) =~ s/\.bam/\.realigned\.bai/;
	    (my $realignedBamBai = $bam) =~ s/\.bam/\.realigned\.bam\.bai/;
	    (my $realignedFlagstat = $bam) =~ s/\.bam/\.realigned\.flagstat/;

        (my $healthCheckPreRealignSlicedBam = $bam) =~ s/\.bam/\.qc.prerealign.sliced\.bam/;
        (my $healthCheckPreRealignSlicedBamBai = $bam) =~ s/\.bam/\.qc.prerealign.sliced\.bam\.bai/;
        (my $healthCheckPostRealignSlicedBam = $bam) =~ s/\.bam/\.qc.postrealign.sliced\.bam/;
        (my $healthCheckPostRealignSlicedBamBai = $bam) =~ s/\.bam/\.qc.postrealign.sliced\.bam\.bai/;
		(my $healthCheckPostRealignSlicedFlagstat = $bam) =~ s/\.bam/\.qc.postrealign.sliced\.flagstat/;
		(my $healthCheckPrePostRealignDiff = $bam) =~ s/\.bam/\.qc.prepostrealign.diff/;
        (my $cpctSlicedBam = $bam) =~ s/\.bam/\.realigned.sliced\.bam/;
	    (my $cpctSlicedBamBai = $bam) =~ s/\.bam/\.realigned.sliced\.bam\.bai/;

        $opt{BAM_FILES}->{$sample} = $realignedBam;

	    say "\t$opt{OUTPUT_DIR}/$sample/mapping/$bam";

	    if (-e "$opt{OUTPUT_DIR}/$sample/logs/Realignment_$sample.done") {
			say "\t WARNING: $opt{OUTPUT_DIR}/$sample/logs/Realignment_$sample.done exists, skipping";
			next;
	    }

	    my $logDir = $opt{OUTPUT_DIR}."/".$sample."/logs";
	    my $jobIDRealign = "Realign_".$sample."_".getJobId();
	    my $bashFile = $opt{OUTPUT_DIR}."/".$sample."/jobs/".$jobIDRealign.".sh";
	    my $jobNative = &jobNative(\%opt,"REALIGNMENT");

	    my $knownIndelFiles = "";
	    my @knownIndelFilesA = ();
	    if ($opt{REALIGNMENT_KNOWN}) {
			foreach my $knownIndelFile (@knownIndelFiles) {
				die "ERROR: $knownIndelFile does not exist" if !-e $knownIndelFile;
				push @knownIndelFilesA, "-known $knownIndelFile";
			}
			$knownIndelFiles = join(" ", @knownIndelFilesA);
	    }

		from_template("Realign.sh.tt", $bashFile, sample => $sample, bam => $bam, logDir => $logDir, jobNative => $jobNative, knownIndelFiles => $knownIndelFiles,
            healthCheckPreRealignSlicedBam => $healthCheckPreRealignSlicedBam, healthCheckPreRealignSlicedBamBai => $healthCheckPreRealignSlicedBamBai, opt => \%opt, runName => $runName);

	    my $qsub = qsubJava(\%opt, "REALIGNMENT_MASTER");
	    if (@{$opt{RUNNING_JOBS}->{$sample}}) {
			system $qsub." -o ".$logDir."/Realignment_".$sample.".out -e ".$logDir."/Realignment_".$sample.".err -N ".$jobIDRealign." -hold_jid ".join(",",@{$opt{RUNNING_JOBS}->{$sample}})." ".$bashFile;
	    } else {
			system $qsub." -o ".$logDir."/Realignment_".$sample.".out -e ".$logDir."/Realignment_".$sample.".err -N ".$jobIDRealign." ".$bashFile;
	    }

	    my $jobIDPostProcess = "RealignPostProcess_".$sample."_".getJobId();
	    my $realignPostProcessScript = $opt{OUTPUT_DIR}."/".$sample."/jobs/".$jobIDPostProcess.".sh";

	    from_template("RealignPostProcess.sh.tt", $realignPostProcessScript, realignedBam => $realignedBam, realignedBai => $realignedBai, realignedBamBai => $realignedBamBai,
		    realignedFlagstat => $realignedFlagstat, flagstat => $flagstat, sample => $sample, logDir => $logDir, cpctSlicedBam => $cpctSlicedBam, cpctSlicedBamBai => $cpctSlicedBamBai,
			healthCheckPreRealignSlicedBam => $healthCheckPreRealignSlicedBam, healthCheckPostRealignSlicedBam => $healthCheckPostRealignSlicedBam,
			healthCheckPostRealignSlicedBamBai => $healthCheckPostRealignSlicedBamBai, healthCheckPostRealignSlicedFlagstat => $healthCheckPostRealignSlicedFlagstat,
			healthCheckPrePostRealignDiff => $healthCheckPrePostRealignDiff, opt => \%opt, runName => $runName);

	    $qsub = qsubTemplate(\%opt, "FLAGSTAT");
	    system $qsub." -o ".$logDir."/RealignmentPostProcess_".$sample.".out -e ".$logDir."/RealignmentPostProcess_".$sample.".err -N ".$jobIDPostProcess." -hold_jid ".$jobIDRealign." ".$realignPostProcessScript;

	    push(@{$opt{RUNNING_JOBS}->{$sample}}, $jobIDRealign);
	    push(@{$opt{RUNNING_JOBS}->{$sample}}, $jobIDPostProcess);
	}

    return \%opt;
}

1;
