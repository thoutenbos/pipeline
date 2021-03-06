package HMF::Pipeline::CopyNumber;

use FindBin::libs;
use discipline;

use File::Basename;
use File::Spec::Functions;

use HMF::Pipeline::Config qw(createDirs addSubDir sampleBamAndJobs sampleControlBamsAndJobs);
use HMF::Pipeline::Job qw(fromTemplate checkReportedDoneFile markDone);
use HMF::Pipeline::Metadata;
use HMF::Pipeline::Sge qw(qsubTemplate);
use HMF::Pipeline::Template qw(writeFromTemplate);

use parent qw(Exporter);
our @EXPORT_OK = qw(run);


sub run {
    my ($opt) = @_;

    say "\n### SCHEDULING COPY NUMBER TOOLS ###";

    if ($opt->{CNV_MODE} eq "sample_control") {
        my ($ref_sample, $tumor_sample, $ref_bam_path, $tumor_bam_path, $joint_name, $running_jobs) = sampleControlBamsAndJobs($opt);
        my $job_id = runSampleCnv($tumor_sample, $ref_sample, $tumor_bam_path, $ref_bam_path, $joint_name, $running_jobs, $opt);
        push @{$opt->{RUNNING_JOBS}->{cnv}}, $job_id;
    } elsif ($opt->{CNV_MODE} eq "sample") {
        foreach my $sample (keys %{$opt->{SAMPLES}}) {
            my ($sample_bam, $running_jobs) = sampleBamAndJobs($sample, $opt);
            my $job_id = runSampleCnv($sample, undef, $sample_bam, undef, $sample, $running_jobs, $opt);
            push @{$opt->{RUNNING_JOBS}->{cnv}}, $job_id;
        }
    }
    return;
}

sub runSampleCnv {
    my ($sample, $control, $sample_bam, $control_bam, $joint_name, $running_jobs, $opt) = @_;

    my $dirs = createDirs(catfile($opt->{OUTPUT_DIR}, "copyNumber", $joint_name));

    $control_bam //= "";
    say "\n$joint_name \t $control_bam \t $sample_bam";

    my @cnv_jobs;
    my $done_file = checkReportedDoneFile($joint_name, undef, $dirs, $opt) or return;
    push @cnv_jobs, runFreec($sample, $control, $sample_bam, $control_bam, $running_jobs, $dirs, $opt) if $opt->{CNV_FREEC} eq "yes";
    push @cnv_jobs, runQDNAseq($sample, $sample_bam, $running_jobs, $dirs, $opt) if $opt->{CNV_QDNASEQ} eq "yes";
    my $job_id = markDone($done_file, \@cnv_jobs, $dirs, $opt);
    return $job_id;
}

sub runFreec {
    my ($sample_name, $control_name, $sample_bam, $control_bam, $running_jobs, $dirs, $opt) = @_;

    say "\n### SCHEDULING FREEC ###";

    $dirs->{freec}{out} = addSubDir($dirs, "freec");

    my ($sample_path, $control_path);
    if ($opt->{FREEC_BAF} eq "yes") {
        $sample_path = $opt->{PILEUP_FILES}->{$sample_name};
        $control_path = $control_name ? $opt->{PILEUP_FILES}->{$control_name} : "";
    } else {
        $sample_path = $sample_bam;
        $control_path = $control_bam;
    }

    my $config_file = catfile($dirs->{freec}{out}, "freec_config.txt");
    writeFromTemplate(
        "FreecConfig.tt",
        $config_file,
        sample_path => $sample_path,
        control_path => $control_path,
        dirs => $dirs,
        opt => $opt,
    );

    my @dependent_jobs = @{$running_jobs};

    my $sample_file_name = fileparse($sample_path);
    my $job_id = fromTemplate(
        "Freec",
        undef,
        1,
        qsubTemplate($opt, "FREEC"),
        \@dependent_jobs,
        $dirs,
        $opt,
        sample_name => $sample_name,
        sample_path => $sample_path,
        control_path => $control_path,
        sample_file_name => $sample_file_name,
        config_file => $config_file,
    );
    return unless $job_id;

    # dependent on implicit FREEC naming. must happen even if .done.
    foreach my $artefact ("${sample_file_name}_ratio_karyotype.pdf", "${sample_file_name}_ratio.txt.png", "${sample_file_name}_CNVs.p.value.txt") {
        HMF::Pipeline::Metadata::linkExtraArtefact(catfile($dirs->{freec}->{out}, $artefact), $opt);
    }

    return $job_id;
}

sub runQDNAseq {
    my ($sample_name, $sample_bam, $running_jobs, $dirs, $opt) = @_;

    say "\n### SCHEDULING QDNASEQ ###";

    $dirs->{qdnaseq}{out} = addSubDir($dirs, "qdnaseq");

    my $job_id = fromTemplate(
        "QDNAseq",
        undef,
        1,
        qsubTemplate($opt, "QDNASEQ"),
        $running_jobs,
        $dirs,
        $opt,
        sample_name => $sample_name,
        sample_bam => $sample_bam,
    );
    return unless $job_id;

    # dependent on implicit QDNAseq naming. must happen even if .done.
    (my $output_vcf = $opt->{BAM_FILES}->{$sample_name}) =~ s/\.bam$/.vcf/;
    foreach my $artefact ($output_vcf, "calls.igv", "copynumber.igv", "segments.igv") {
        HMF::Pipeline::Metadata::linkExtraArtefact(catfile($dirs->{qdnaseq}->{out}, $artefact), $opt);
    }

    return $job_id;
}

1;